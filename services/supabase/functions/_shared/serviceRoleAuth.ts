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
  envSecretKeys?: string;
  envServerApiKey?: string;
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
 * `SUPABASE_SERVER_API_KEY` is an explicit deployment override,
 * `SUPABASE_SECRET_KEYS` is the platform-managed dictionary of current
 * `sb_secret_...` keys, and `SUPABASE_SERVICE_ROLE_KEY` is the migration
 * fallback for the legacy JWT.
 */
export function serverApiKeyOptionsFromEnvironment(): ServiceRoleAuthOptions {
  return {
    envServerApiKey: Deno.env.get("SUPABASE_SERVER_API_KEY") ?? "",
    envSecretKeys: Deno.env.get("SUPABASE_SECRET_KEYS") ?? "",
    envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  };
}

export function serviceRoleRequestHeaders(
  serverApiKey: string,
  destination: "database" | "functions" | "auth" | "storage" = "functions",
): Record<string, string> {
  if (!isSupportedServerApiKey(serverApiKey)) {
    throw new ServerApiKeyConfigurationError(
      "invalid_secret_key_configuration",
    );
  }

  const headers: Record<string, string> = {
    apikey: serverApiKey,
  };

  if (serverApiKey.startsWith("sb_secret_")) {
    if (destination === "functions") {
      headers["x-supabase-server-key"] = serverApiKey;
    } else {
      headers.Authorization = `Bearer ${serverApiKey}`;
    }
  } else {
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

const CURRENT_SECRET_KEY_PREFIX = "sb_secret_";
const MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20;
const HS256_BASE64URL_SIGNATURE_LENGTH = 43;

function isCurrentSecretKey(value: string): boolean {
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
function isLegacyServiceRoleJwt(value: string): boolean {
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
  const customKey = req.headers.get("x-supabase-server-key")?.trim() ?? "";
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

  const token = customKey || apiKey || bearerToken;
  return token ? { token } : { reason: "missing_token" };
}

function parseSecretKeyConfiguration(
  rawSecretKeys: string | undefined,
): SecretKeyConfigurationResult {
  const raw = rawSecretKeys?.trim() ?? "";
  if (!raw) return { entries: [], valid: true };

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      if (typeof parsed === "string" && isCurrentSecretKey(parsed)) {
        return { entries: [{ name: "default", key: parsed }], valid: true };
      }
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
    if (isCurrentSecretKey(raw)) {
      return { entries: [{ name: "default", key: raw }], valid: true };
    }
    return { entries: [], valid: false };
  }
}

function matchesAnyConfiguredKey(
  token: string,
  entries: Array<{ name: string; key: string }>,
): boolean {
  let matched = false;
  for (const entry of entries) {
    const currentMatch = timingSafeCompare(token, entry.key);
    matched = currentMatch || matched;
  }
  return matched;
}

function preferredServerApiKey(
  legacyServiceRoleKey: string,
  explicitServerApiKey: string,
  secretKeyConfiguration: SecretKeyConfigurationResult,
): string | null {
  const namedDefault = secretKeyConfiguration.entries.find(
    (entry) => entry.name === "default",
  );
  return explicitServerApiKey ||
    namedDefault?.key ||
    secretKeyConfiguration.entries[0]?.key ||
    legacyServiceRoleKey ||
    null;
}

export function resolveServerApiKey(
  options: ServiceRoleAuthOptions,
): ServerApiKeyResult {
  const legacyServiceRoleKey = options.envServiceRoleKey?.trim() ?? "";
  const explicitServerApiKey = options.envServerApiKey?.trim() ?? "";
  if (
    (legacyServiceRoleKey &&
      !isSupportedServerApiKey(legacyServiceRoleKey)) ||
    (explicitServerApiKey &&
      !isSupportedServerApiKey(explicitServerApiKey))
  ) {
    return { ok: false, reason: "invalid_secret_key_configuration" };
  }

  const secretKeyConfiguration = parseSecretKeyConfiguration(
    options.envSecretKeys,
  );

  // An explicit or legacy key remains available during a malformed
  // platform-managed dictionary rollout. Unknown named keys still fail closed.
  if (!secretKeyConfiguration.valid) {
    const fallbackKey = explicitServerApiKey || legacyServiceRoleKey;
    return fallbackKey
      ? { ok: true, serverApiKey: fallbackKey }
      : { ok: false, reason: "invalid_secret_key_configuration" };
  }

  const serverApiKey = preferredServerApiKey(
    legacyServiceRoleKey,
    explicitServerApiKey,
    secretKeyConfiguration,
  );
  return serverApiKey
    ? { ok: true, serverApiKey }
    : { ok: false, reason: "no_configured_keys" };
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

  const legacyServiceRoleKey = options.envServiceRoleKey?.trim() ?? "";
  const explicitServerApiKey = options.envServerApiKey?.trim() ?? "";
  if (
    (legacyServiceRoleKey &&
      !isSupportedServerApiKey(legacyServiceRoleKey)) ||
    (explicitServerApiKey &&
      !isSupportedServerApiKey(explicitServerApiKey))
  ) {
    return { ok: false, reason: "invalid_secret_key_configuration" };
  }

  if (
    (legacyServiceRoleKey &&
      timingSafeCompare(credential.token, legacyServiceRoleKey)) ||
    (explicitServerApiKey &&
      timingSafeCompare(credential.token, explicitServerApiKey))
  ) {
    const secretKeyConfiguration = parseSecretKeyConfiguration(
      options.envSecretKeys,
    );
    return {
      ok: true,
      serverApiKey: secretKeyConfiguration.valid
        ? preferredServerApiKey(
          legacyServiceRoleKey,
          explicitServerApiKey,
          secretKeyConfiguration,
        ) ?? credential.token
        : explicitServerApiKey || legacyServiceRoleKey,
    };
  }

  const secretKeyConfiguration = parseSecretKeyConfiguration(
    options.envSecretKeys,
  );
  if (!secretKeyConfiguration.valid) {
    return { ok: false, reason: "invalid_secret_key_configuration" };
  }

  if (
    !legacyServiceRoleKey &&
    !explicitServerApiKey &&
    secretKeyConfiguration.entries.length === 0
  ) {
    return { ok: false, reason: "no_configured_keys" };
  }

  if (
    !matchesAnyConfiguredKey(
      credential.token,
      secretKeyConfiguration.entries,
    )
  ) {
    return { ok: false, reason: "token_mismatch" };
  }

  const serverApiKey = preferredServerApiKey(
    legacyServiceRoleKey,
    explicitServerApiKey,
    secretKeyConfiguration,
  );
  return serverApiKey
    ? { ok: true, serverApiKey }
    : { ok: false, reason: "no_configured_keys" };
}

export function authorizeServiceRoleRequestFromEnvironment(
  req: Request,
): ServiceRoleAuthResult {
  return authorizeServiceRoleRequest(
    req,
    serverApiKeyOptionsFromEnvironment(),
  );
}
