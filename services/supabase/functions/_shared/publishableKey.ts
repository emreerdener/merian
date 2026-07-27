export type PublicApiKeyConfigurationFailureReason =
  | "no_configured_keys"
  | "invalid_publishable_key_configuration";

export interface PublicApiKeyOptions {
  envPublishableKeys?: string;
  envAnonKey?: string;
}

export type PublicApiKeyResolution =
  | {
    ok: true;
    publicApiKey: string;
    acceptedPublicApiKeys: string[];
  }
  | {
    ok: false;
    reason: PublicApiKeyConfigurationFailureReason;
  };

export class PublicApiKeyConfigurationError extends Error {
  constructor(readonly reason: PublicApiKeyConfigurationFailureReason) {
    super(`Public API key unavailable: ${reason}`);
    this.name = "PublicApiKeyConfigurationError";
  }
}

const PUBLISHABLE_KEY_PREFIX = "sb_publishable_";
const MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20;
const HS256_BASE64URL_SIGNATURE_LENGTH = 43;

interface NamedPublishableKey {
  name: string;
  key: string;
}

function decodeBase64UrlJson(
  segment: string,
): Record<string, unknown> | null {
  if (!/^[A-Za-z0-9_-]+$/.test(segment)) return null;

  try {
    const paddingLength = (4 - (segment.length % 4)) % 4;
    const base64 = segment.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat(paddingLength);
    const bytes = Uint8Array.from(
      atob(base64),
      (character) => character.charCodeAt(0),
    );
    const parsed: unknown = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export function isCurrentPublishableKey(value: string): boolean {
  const suffix = value.slice(PUBLISHABLE_KEY_PREFIX.length);
  return value.startsWith(PUBLISHABLE_KEY_PREFIX) &&
    suffix.length >= MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH &&
    /^[A-Za-z0-9_-]+$/.test(suffix);
}

export function isLegacyAnonJwt(value: string): boolean {
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
  return header?.alg === "HS256" && payload?.role === "anon";
}

function parsePublishableKeys(
  rawPublishableKeys: string | undefined,
): { entries: NamedPublishableKey[]; valid: boolean } {
  const raw = rawPublishableKeys ?? "";
  if (!raw) return { entries: [], valid: true };

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { entries: [], valid: false };
    }

    const entries: NamedPublishableKey[] = [];
    for (const [name, value] of Object.entries(parsed)) {
      if (
        !name ||
        name.trim() !== name ||
        typeof value !== "string" ||
        !isCurrentPublishableKey(value)
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

export function resolvePublicApiKeys(
  options: PublicApiKeyOptions,
): PublicApiKeyResolution {
  const legacyAnonKey = options.envAnonKey ?? "";
  const legacyAnonKeyConfigured = legacyAnonKey.length > 0;
  const legacyAnonKeyValid = !legacyAnonKeyConfigured ||
    isLegacyAnonJwt(legacyAnonKey);
  const publishableKeys = parsePublishableKeys(options.envPublishableKeys);
  if (publishableKeys.valid && publishableKeys.entries.length > 0) {
    const namedDefault = publishableKeys.entries.find(
      (entry) => entry.name === "default",
    );
    const publicApiKey = namedDefault?.key ??
      publishableKeys.entries[0].key;
    return {
      ok: true,
      publicApiKey,
      acceptedPublicApiKeys: [
        ...new Set([
          ...publishableKeys.entries.map((entry) => entry.key),
          ...(legacyAnonKeyConfigured && legacyAnonKeyValid
            ? [legacyAnonKey]
            : []),
        ]),
      ],
    };
  }

  // The hosted dictionary and legacy scalar are independent migration
  // sources. A valid source remains usable during an incident in the other;
  // malformed values never become accepted public-key candidates.
  if (legacyAnonKeyConfigured && legacyAnonKeyValid) {
    return {
      ok: true,
      publicApiKey: legacyAnonKey,
      acceptedPublicApiKeys: [legacyAnonKey],
    };
  }
  return !publishableKeys.valid || !legacyAnonKeyValid
    ? {
      ok: false,
      reason: "invalid_publishable_key_configuration",
    }
    : { ok: false, reason: "no_configured_keys" };
}

export function publicApiKeyOptionsFromEnvironment(): PublicApiKeyOptions {
  return {
    envPublishableKeys: Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "",
    envAnonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  };
}

export function requirePublicApiKeys(
  options: PublicApiKeyOptions,
): {
  publicApiKey: string;
  acceptedPublicApiKeys: string[];
} {
  const result = resolvePublicApiKeys(options);
  if (!result.ok) {
    throw new PublicApiKeyConfigurationError(result.reason);
  }
  return result;
}

export function requirePublicApiKeysFromEnvironment(): {
  publicApiKey: string;
  acceptedPublicApiKeys: string[];
} {
  return requirePublicApiKeys(publicApiKeyOptionsFromEnvironment());
}

export function requirePublicApiKeyFromEnvironment(): string {
  return requirePublicApiKeysFromEnvironment().publicApiKey;
}
