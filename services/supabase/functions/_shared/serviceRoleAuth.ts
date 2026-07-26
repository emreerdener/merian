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
  envServiceRoleKey: string;
  envSecretKeys?: string;
}

export function serviceRoleRequestHeaders(
  serverApiKey: string,
): Record<string, string> {
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
  const raw = rawSecretKeys?.trim() ?? "";
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
        !value.startsWith("sb_secret_") ||
        value.trim() !== value ||
        value.length === "sb_secret_".length
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
  secretKeyConfiguration: SecretKeyConfigurationResult,
): string | null {
  const namedDefault = secretKeyConfiguration.entries.find(
    (entry) => entry.name === "default",
  );
  return namedDefault?.key ??
    secretKeyConfiguration.entries[0]?.key ??
    (legacyServiceRoleKey || null);
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

  const legacyServiceRoleKey = options.envServiceRoleKey.trim();
  if (
    legacyServiceRoleKey &&
    timingSafeCompare(credential.token, legacyServiceRoleKey)
  ) {
    const secretKeyConfiguration = parseSecretKeyConfiguration(
      options.envSecretKeys,
    );
    return {
      ok: true,
      serverApiKey: secretKeyConfiguration.valid
        ? preferredServerApiKey(
          legacyServiceRoleKey,
          secretKeyConfiguration,
        ) ?? legacyServiceRoleKey
        : legacyServiceRoleKey,
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
    secretKeyConfiguration,
  );
  return serverApiKey
    ? { ok: true, serverApiKey }
    : { ok: false, reason: "no_configured_keys" };
}
