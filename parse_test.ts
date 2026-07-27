import { assert } from "https://deno.land/std@0.224.0/testing/asserts.ts";

const CURRENT_SECRET_KEY_PREFIX = "sb_secret_";
const MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20;

function isCurrentSecretKey(value: string): boolean {
  const suffix = value.slice(CURRENT_SECRET_KEY_PREFIX.length);
  return value.startsWith(CURRENT_SECRET_KEY_PREFIX) &&
    suffix.length >= MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH &&
    /^[A-Za-z0-9_-]+$/.test(suffix);
}

function parseSecretKeyConfiguration(
  rawSecretKeys: string | undefined,
): { entries: Array<{ name: string; key: string }>; valid: boolean } {
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

console.log("Raw string test:");
const testKey = "sb_secret_XqnMh1234567890abcdefghijklmnopqrstuvwxyz";
console.log(parseSecretKeyConfiguration(testKey));
