import { timingSafeCompare } from "./http.ts";

export type ServiceRoleAuthFailureReason =
  | "missing_token"
  | "invalid_authorization_header"
  | "invalid_credential_transport"
  | "conflicting_credentials"
  | "no_configured_keys"
  | "invalid_secret_key_configuration"
  | "token_mismatch";

export type ServiceRoleAuthResult =
  | { ok: true; serverApiKey: string }
  | { ok: false; reason: ServiceRoleAuthFailureReason };

export interface ServiceRoleAuthOptions {
  envServiceRoleKey?: string;
  envSecretKey?: string;
  envSecretKeys?: string;
  envServerApiKey?: string;
  envSynchronizedServerApiKey?: string;
}

export type ServerApiKeyResult =
  | { ok: true; serverApiKey: string }
  | {
    ok: false;
    reason: "no_configured_keys" | "invalid_secret_key_configuration";
  };

export class ServerApiKeyConfigurationError extends Error {
  constructor(
    readonly reason:
      | "no_configured_keys"
      | "invalid_secret_key_configuration",
  ) {
    super(`Server API key unavailable: ${reason}`);
    this.name = "ServerApiKeyConfigurationError";
  }
}

/**
 * Reads every supported server-key source in one place.
 *
 * `SUPABASE_SERVER_API_KEY` is an explicit CI/local override,
 * `MERIAN_SUPABASE_SERVER_API_KEY` is the non-reserved hosted fallback
 * synchronized by the production deploy,
 * `SUPABASE_SECRET_KEYS` is the platform-managed dictionary of current
 * `sb_secret_...` keys, `SUPABASE_SECRET_KEY` is the local/manual fallback,
 * and `SUPABASE_SERVICE_ROLE_KEY` is the migration fallback for the legacy
 * JWT.
 */
export function serverApiKeyOptionsFromEnvironment(): ServiceRoleAuthOptions {
  return {
    envServerApiKey: Deno.env.get("SUPABASE_SERVER_API_KEY") ?? "",
    envSynchronizedServerApiKey:
      Deno.env.get("MERIAN_SUPABASE_SERVER_API_KEY") ?? "",
    envSecretKeys: Deno.env.get("SUPABASE_SECRET_KEYS") ?? "",
    envSecretKey: Deno.env.get("SUPABASE_SECRET_KEY") ?? "",
    envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  };
}

/**
 * Builds format-aware server credentials.
 *
 * Opaque API keys belong in `apikey`, never in Bearer transport. Legacy
 * service-role JWTs remain valid Bearer tokens during the migration window.
 */
export function serviceRoleRequestHeaders(
  serverApiKey: string,
): Record<string, string> {
  if (!isSupportedServerApiKey(serverApiKey)) {
    throw new ServerApiKeyConfigurationError(
      "invalid_secret_key_configuration",
    );
  }

  const headers: Record<string, string> = {
    apikey: serverApiKey,
  };

  if (!serverApiKey.startsWith("sb_secret_")) {
    headers.Authorization = `Bearer ${serverApiKey}`;
  }

  return headers;
}

type RequestCredentialResult = {
  token?: string;
  reason?: ServiceRoleAuthFailureReason;
};

type SecretKeyConfigurationResult = {
  entries: Array<{ name: string; key: string }>;
  valid: boolean;
};

type ScalarKeyConfiguration = {
  configured: boolean;
  key: string;
  valid: boolean;
};

type ClassifiedServerKeyConfiguration = {
  explicit: ScalarKeyConfiguration;
  synchronized: ScalarKeyConfiguration;
  named: SecretKeyConfigurationResult;
  singular: ScalarKeyConfiguration;
  legacy: ScalarKeyConfiguration;
};

const CURRENT_SECRET_KEY_PREFIX = "sb_secret_";
const MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20;
const HS256_BASE64URL_SIGNATURE_LENGTH = 43;

export function isCurrentSecretKey(value: string): boolean {
  const suffix = value.slice(CURRENT_SECRET_KEY_PREFIX.length);
  return value.startsWith(CURRENT_SECRET_KEY_PREFIX) &&
    suffix.length >= MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH &&
    /^[A-Za-z0-9_-]+$/.test(suffix);
}

function decodeBase64UrlJson(
  segment: string,
): Record<string, unknown> | null {
  if (!/^[A-Za-z0-9_-]+$/.test(segment)) return null;

  try {
    const paddingLength = (4 - (segment.length % 4)) % 4;
    const base64 = segment.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat(paddingLength);
    const decoded = Uint8Array.from(
      atob(base64),
      (character) => character.charCodeAt(0),
    );
    const parsed: unknown = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(decoded),
    );
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

/**
 * Classifies the platform-issued legacy service-role JWT without treating an
 * arbitrary JWT as privileged. Signature verification remains PostgreSQL's
 * responsibility; this check prevents an anon/user JWT copied into a server
 * key variable from becoming an authorization oracle through exact matching.
 */
export function isLegacyServiceRoleJwt(value: string): boolean {
  if (!value || value.trim() !== value) return false;
  const segments = value.split(".");
  if (
    segments.length !== 3 ||
    segments.some((segment) => segment.length === 0) ||
    segments[2].length !== HS256_BASE64URL_SIGNATURE_LENGTH ||
    !/^[A-Za-z0-9_-]+$/.test(segments[2])
  ) {
    return false;
  }

  const header = decodeBase64UrlJson(segments[0]);
  const payload = decodeBase64UrlJson(segments[1]);
  return header?.alg === "HS256" && payload?.role === "service_role";
}

function isSupportedServerApiKey(value: string): boolean {
  return isCurrentSecretKey(value) || isLegacyServiceRoleJwt(value);
}

function requestCredential(req: Request): RequestCredentialResult {
  const authorization = req.headers.get("Authorization")?.trim() ?? "";
  const bearerMatch = authorization.match(/^Bearer\s+([^\s]+)$/i);
  if (authorization.length > 0 && !bearerMatch) {
    return { reason: "invalid_authorization_header" };
  }

  const bearerToken = bearerMatch?.[1]?.trim() ?? "";
  const apiKey = req.headers.get("apikey")?.trim() ?? "";
  if (
    bearerToken.startsWith("sb_secret_") ||
    bearerToken.startsWith("sb_publishable_")
  ) {
    return { reason: "invalid_credential_transport" };
  }
  if (bearerToken && apiKey && !timingSafeCompare(bearerToken, apiKey)) {
    return { reason: "conflicting_credentials" };
  }

  const token = apiKey || bearerToken;
  return token ? { token } : { reason: "missing_token" };
}

function parseSecretKeyConfiguration(
  rawSecretKeys: string | undefined,
): SecretKeyConfigurationResult {
  const raw = rawSecretKeys ?? "";
  if (!raw) return { entries: [], valid: true };

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { entries: [], valid: false };
    }

    const rawEntries = Object.entries(parsed);
    const entries: Array<{ name: string; key: string }> = [];
    for (const [name, value] of rawEntries) {
      if (
        !name ||
        name.trim() !== name ||
        typeof value !== "string" ||
        !isCurrentSecretKey(value)
      ) {
        return { entries: [], valid: false };
      }
      entries.push({ name, key: value });
    }
    entries.sort((left, right) => left.name.localeCompare(right.name));
    return { entries, valid: true };
  } catch {
    return { entries: [], valid: false };
  }
}

function classifyScalarKey(
  rawValue: string | undefined,
  validator: (value: string) => boolean,
): ScalarKeyConfiguration {
  const key = rawValue ?? "";
  return {
    configured: key.length > 0,
    key,
    valid: key.length === 0 || validator(key),
  };
}

function classifyServerKeyConfiguration(
  options: ServiceRoleAuthOptions,
): ClassifiedServerKeyConfiguration {
  return {
    explicit: classifyScalarKey(
      options.envServerApiKey,
      isSupportedServerApiKey,
    ),
    synchronized: classifyScalarKey(
      options.envSynchronizedServerApiKey,
      isSupportedServerApiKey,
    ),
    named: parseSecretKeyConfiguration(options.envSecretKeys),
    singular: classifyScalarKey(options.envSecretKey, isCurrentSecretKey),
    legacy: classifyScalarKey(
      options.envServiceRoleKey,
      isLegacyServiceRoleJwt,
    ),
  };
}

function matchesAnyConfiguredKey(
  token: string,
  configuredKeys: string[],
): boolean {
  let matched = false;
  for (const configuredKey of configuredKeys) {
    const currentMatch = timingSafeCompare(token, configuredKey);
    matched = currentMatch || matched;
  }
  return matched;
}

function preferredNamedSecretKey(
  configuration: SecretKeyConfigurationResult,
): string | null {
  if (!configuration.valid) return null;
  const namedDefault = configuration.entries.find(
    (entry) => entry.name === "default",
  );
  return namedDefault?.key ||
    configuration.entries[0]?.key ||
    null;
}

function preferredValidServerApiKey(
  configuration: ClassifiedServerKeyConfiguration,
): string | null {
  return (configuration.explicit.valid ? configuration.explicit.key : "") ||
    (configuration.synchronized.valid ? configuration.synchronized.key : "") ||
    preferredNamedSecretKey(configuration.named) ||
    (configuration.singular.valid ? configuration.singular.key : "") ||
    (configuration.legacy.valid ? configuration.legacy.key : "") ||
    null;
}

function validConfiguredServerKeys(
  configuration: ClassifiedServerKeyConfiguration,
): string[] {
  return [
    ...(configuration.explicit.configured && configuration.explicit.valid
      ? [configuration.explicit.key]
      : []),
    ...(configuration.synchronized.configured &&
        configuration.synchronized.valid
      ? [configuration.synchronized.key]
      : []),
    ...(configuration.named.valid
      ? configuration.named.entries.map((entry) => entry.key)
      : []),
    ...(configuration.singular.configured && configuration.singular.valid
      ? [configuration.singular.key]
      : []),
    ...(configuration.legacy.configured && configuration.legacy.valid
      ? [configuration.legacy.key]
      : []),
  ];
}

function hasInvalidServerKeySource(
  configuration: ClassifiedServerKeyConfiguration,
): boolean {
  return !configuration.explicit.valid ||
    !configuration.synchronized.valid ||
    !configuration.named.valid ||
    !configuration.singular.valid ||
    !configuration.legacy.valid;
}

function configuredScalarResult(
  configuration: ScalarKeyConfiguration,
): ServerApiKeyResult | null {
  if (!configuration.configured) return null;
  return configuration.valid
    ? { ok: true, serverApiKey: configuration.key }
    : { ok: false, reason: "invalid_secret_key_configuration" };
}

function namedServerApiKey(
  configuration: SecretKeyConfigurationResult,
): string | null {
  return configuration.valid ? preferredNamedSecretKey(configuration) : null;
}

function fallbackServerApiKey(
  singular: ScalarKeyConfiguration,
  legacy: ScalarKeyConfiguration,
): ServerApiKeyResult | null {
  return configuredScalarResult(singular) ||
    configuredScalarResult(legacy);
}

function unresolvedServerApiKey(
  named: SecretKeyConfigurationResult,
): ServerApiKeyResult {
  return named.valid
    ? { ok: false, reason: "no_configured_keys" }
    : { ok: false, reason: "invalid_secret_key_configuration" };
}

function preferredServerApiKey(
  configuration: ClassifiedServerKeyConfiguration,
): ServerApiKeyResult {
  const explicit = configuredScalarResult(configuration.explicit);
  if (explicit) return explicit;

  const synchronized = configuredScalarResult(configuration.synchronized);
  if (synchronized) return synchronized;

  const named = namedServerApiKey(configuration.named);
  if (named) return { ok: true, serverApiKey: named };

  return fallbackServerApiKey(
    configuration.singular,
    configuration.legacy,
  ) ||
    unresolvedServerApiKey(configuration.named);
}

export function resolveServerApiKey(
  options: ServiceRoleAuthOptions,
): ServerApiKeyResult {
  return preferredServerApiKey(classifyServerKeyConfiguration(options));
}

export function requireServerApiKey(
  options: ServiceRoleAuthOptions,
): string {
  const result = resolveServerApiKey(options);
  if (!result.ok) {
    throw new ServerApiKeyConfigurationError(result.reason);
  }
  return result.serverApiKey;
}

export function resolveServerApiKeyFromEnvironment(): ServerApiKeyResult {
  return resolveServerApiKey(serverApiKeyOptionsFromEnvironment());
}

export function requireServerApiKeyFromEnvironment(): string {
  const result = resolveServerApiKeyFromEnvironment();
  if (!result.ok) {
    throw new ServerApiKeyConfigurationError(result.reason);
  }
  return result.serverApiKey;
}

export function authorizeServiceRoleRequest(
  req: Request,
  options: ServiceRoleAuthOptions,
): ServiceRoleAuthResult {
  const credential = requestCredential(req);
  if (!credential.token) {
    return {
      ok: false,
      reason: credential.reason ?? "missing_token",
    };
  }

  const configuration = classifyServerKeyConfiguration(options);
  const validKeys = validConfiguredServerKeys(configuration);

  // Each environment source is an independent migration input. A malformed
  // source contributes no authorization candidate, but it must not veto an
  // exact key supplied by another independently valid source. If nothing
  // matches, any malformed source still produces a fail-closed configuration
  // error instead of degrading to a normal token mismatch.
  if (matchesAnyConfiguredKey(credential.token, validKeys)) {
    const serverApiKey = preferredValidServerApiKey(configuration);
    return serverApiKey
      ? { ok: true, serverApiKey }
      : { ok: false, reason: "no_configured_keys" };
  }

  if (hasInvalidServerKeySource(configuration)) {
    return { ok: false, reason: "invalid_secret_key_configuration" };
  }
  return validKeys.length === 0
    ? { ok: false, reason: "no_configured_keys" }
    : { ok: false, reason: "token_mismatch" };
}

export function authorizeServiceRoleRequestFromEnvironment(
  req: Request,
): ServiceRoleAuthResult {
  return authorizeServiceRoleRequest(
    req,
    serverApiKeyOptionsFromEnvironment(),
  );
}
