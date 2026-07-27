import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  isCurrentPublishableKey,
  isLegacyAnonJwt,
  type PublicApiKeyResolution,
  resolvePublicApiKeys,
} from "./publishableKey.ts";

function base64UrlJson(value: Record<string, unknown>): string {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function legacyJwt(role: string): string {
  return `${base64UrlJson({ alg: "HS256", typ: "JWT" })}.${
    base64UrlJson({ iss: "supabase", role })
  }.${"a".repeat(43)}`;
}

const DEFAULT_PUBLISHABLE_KEY = `sb_publishable_${"a".repeat(20)}`;
const SECONDARY_PUBLISHABLE_KEY = `sb_publishable_${"b".repeat(20)}`;
const LEGACY_ANON_KEY = legacyJwt("anon");

Deno.test("publishable-key classifier is strict", () => {
  assertEquals(isCurrentPublishableKey(DEFAULT_PUBLISHABLE_KEY), true);
  assertEquals(isCurrentPublishableKey("sb_publishable_too-short"), false);
  assertEquals(
    isCurrentPublishableKey(`sb_publishable_${"a".repeat(19)}!`),
    false,
  );
});

Deno.test("legacy anon classifier rejects other JWT roles and algorithms", () => {
  assertEquals(isLegacyAnonJwt(LEGACY_ANON_KEY), true);
  assertEquals(isLegacyAnonJwt(legacyJwt("authenticated")), false);
  assertEquals(isLegacyAnonJwt(legacyJwt("service_role")), false);

  const wrongAlgorithm = `${base64UrlJson({ alg: "RS256", typ: "JWT" })}.${
    base64UrlJson({ role: "anon" })
  }.${"a".repeat(43)}`;
  assertEquals(isLegacyAnonJwt(wrongAlgorithm), false);
});

Deno.test("public resolver prefers default and accepts rotation keys", () => {
  assertEquals(
    resolvePublicApiKeys({
      envPublishableKeys: JSON.stringify({
        secondary: SECONDARY_PUBLISHABLE_KEY,
        default: DEFAULT_PUBLISHABLE_KEY,
      }),
      envAnonKey: LEGACY_ANON_KEY,
    }),
    {
      ok: true,
      publicApiKey: DEFAULT_PUBLISHABLE_KEY,
      acceptedPublicApiKeys: [
        DEFAULT_PUBLISHABLE_KEY,
        SECONDARY_PUBLISHABLE_KEY,
        LEGACY_ANON_KEY,
      ],
    },
  );
});

Deno.test("public resolver deterministically selects a non-default key", () => {
  assertEquals(
    resolvePublicApiKeys({
      envPublishableKeys: JSON.stringify({
        zebra: SECONDARY_PUBLISHABLE_KEY,
        alpha: DEFAULT_PUBLISHABLE_KEY,
      }),
    }),
    {
      ok: true,
      publicApiKey: DEFAULT_PUBLISHABLE_KEY,
      acceptedPublicApiKeys: [
        DEFAULT_PUBLISHABLE_KEY,
        SECONDARY_PUBLISHABLE_KEY,
      ],
    },
  );
});

Deno.test("public resolver falls back during malformed JSON rollout", () => {
  assertEquals(
    resolvePublicApiKeys({
      envPublishableKeys: "{malformed",
      envAnonKey: LEGACY_ANON_KEY,
    }),
    {
      ok: true,
      publicApiKey: LEGACY_ANON_KEY,
      acceptedPublicApiKeys: [LEGACY_ANON_KEY],
    },
  );
});

Deno.test("public resolver isolates malformed legacy fallback from a valid hosted dictionary", () => {
  assertEquals(
    resolvePublicApiKeys({
      envPublishableKeys: JSON.stringify({
        default: DEFAULT_PUBLISHABLE_KEY,
      }),
      envAnonKey: "not-an-anon-jwt",
    }),
    {
      ok: true,
      publicApiKey: DEFAULT_PUBLISHABLE_KEY,
      acceptedPublicApiKeys: [DEFAULT_PUBLISHABLE_KEY],
    },
  );
});

Deno.test("public-key sources preserve resolution invariants across every configuration state", () => {
  type SourceState = "absent" | "valid" | "invalid";
  const sourceStates: SourceState[] = ["absent", "valid", "invalid"];

  for (const named of sourceStates) {
    for (const legacy of sourceStates) {
      const resolution = resolvePublicApiKeys({
        envPublishableKeys: named === "valid"
          ? JSON.stringify({ default: DEFAULT_PUBLISHABLE_KEY })
          : named === "invalid"
          ? "{"
          : "",
        envAnonKey: legacy === "valid"
          ? LEGACY_ANON_KEY
          : legacy === "invalid"
          ? legacyJwt("service_role")
          : "",
      });

      const expected: PublicApiKeyResolution = named === "valid"
        ? {
          ok: true,
          publicApiKey: DEFAULT_PUBLISHABLE_KEY,
          acceptedPublicApiKeys: [
            DEFAULT_PUBLISHABLE_KEY,
            ...(legacy === "valid" ? [LEGACY_ANON_KEY] : []),
          ],
        }
        : legacy === "valid"
        ? {
          ok: true,
          publicApiKey: LEGACY_ANON_KEY,
          acceptedPublicApiKeys: [LEGACY_ANON_KEY],
        }
        : named === "invalid" || legacy === "invalid"
        ? {
          ok: false,
          reason: "invalid_publishable_key_configuration",
        }
        : { ok: false, reason: "no_configured_keys" };

      assertEquals(
        resolution,
        expected,
        `Resolution failed for ${named}/${legacy}`,
      );
    }
  }
});

Deno.test("public resolver never normalizes malformed scalar credentials", () => {
  assertEquals(
    resolvePublicApiKeys({
      envAnonKey: ` ${LEGACY_ANON_KEY} `,
    }),
    {
      ok: false,
      reason: "invalid_publishable_key_configuration",
    },
  );
});

Deno.test("public resolver rejects malformed or absent configuration", () => {
  assertEquals(
    resolvePublicApiKeys({
      envPublishableKeys: JSON.stringify({
        default: "sb_publishable_invalid!",
      }),
    }),
    {
      ok: false,
      reason: "invalid_publishable_key_configuration",
    },
  );
  assertEquals(
    resolvePublicApiKeys({ envAnonKey: legacyJwt("service_role") }),
    {
      ok: false,
      reason: "invalid_publishable_key_configuration",
    },
  );
  assertEquals(resolvePublicApiKeys({}), {
    ok: false,
    reason: "no_configured_keys",
  });
});
