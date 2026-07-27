export type ServerApiKeySources = {
  explicitServerApiKey?: string;
  platformSecretKeys?: string;
  legacyServiceRoleKey?: string;
};

export type ServerApiKeyResolution =
  | { ok: true; key: string }
  | {
    ok: false;
    reason: "missing_server_api_key" | "invalid_server_api_key_configuration";
  };

type SecretKeyConfiguration = {
  keys: Array<{ name: string; key: string }>;
  valid: boolean;
};

type ScalarKeyConfiguration = {
  configured: boolean;
  key: string;
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

function parsePlatformSecretKeys(rawValue: string): SecretKeyConfiguration {
  if (!rawValue) return { keys: [], valid: true };

  try {
    const parsed: unknown = JSON.parse(rawValue);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { keys: [], valid: false };
    }

    const keys: Array<{ name: string; key: string }> = [];
    for (const [name, value] of Object.entries(parsed)) {
      if (
        !name ||
        name.trim() !== name ||
        typeof value !== "string" ||
        !isCurrentSecretKey(value)
      ) {
        return { keys: [], valid: false };
      }
      keys.push({ name, key: value });
    }
    keys.sort((left, right) => left.name.localeCompare(right.name));
    return { keys, valid: true };
  } catch {
    return { keys: [], valid: false };
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

export function resolveServerApiKeySources(
  sources: ServerApiKeySources,
): ServerApiKeyResolution {
  // Resolve at each priority point instead of globally validating every
  // migration source. A configured malformed override still fails, while a
  // valid selected source is not vetoed by an unrelated lower fallback.
  const explicitServerApiKey = classifyScalarKey(
    sources.explicitServerApiKey,
    isSupportedServerApiKey,
  );
  if (explicitServerApiKey.configured) {
    return explicitServerApiKey.valid
      ? { ok: true, key: explicitServerApiKey.key }
      : { ok: false, reason: "invalid_server_api_key_configuration" };
  }

  const secretKeyConfiguration = parsePlatformSecretKeys(
    sources.platformSecretKeys ?? "",
  );
  if (secretKeyConfiguration.valid && secretKeyConfiguration.keys.length > 0) {
    const namedDefault = secretKeyConfiguration.keys.find(
      (entry) => entry.name === "default",
    );
    return {
      ok: true,
      key: namedDefault?.key ?? secretKeyConfiguration.keys[0].key,
    };
  }

  const legacyServiceRoleKey = classifyScalarKey(
    sources.legacyServiceRoleKey,
    isLegacyServiceRoleJwt,
  );
  if (legacyServiceRoleKey.configured) {
    return legacyServiceRoleKey.valid
      ? { ok: true, key: legacyServiceRoleKey.key }
      : { ok: false, reason: "invalid_server_api_key_configuration" };
  }

  return secretKeyConfiguration.valid
    ? { ok: false, reason: "missing_server_api_key" }
    : { ok: false, reason: "invalid_server_api_key_configuration" };
}
