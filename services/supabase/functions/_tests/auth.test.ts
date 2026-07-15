import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authFailureCode,
  bearerTokenFromAuthorizationHeader,
  validateVerifiedClaims,
} from "../_shared/auth.ts";

Deno.test("bearerTokenFromAuthorizationHeader extracts bearer token", () => {
  assertEquals(
    bearerTokenFromAuthorizationHeader(
      "Bearer eyJhbGciOiJFUzI1NiJ9.payload.signature",
    ),
    "eyJhbGciOiJFUzI1NiJ9.payload.signature",
  );
});

Deno.test("bearerTokenFromAuthorizationHeader accepts lowercase scheme", () => {
  assertEquals(
    bearerTokenFromAuthorizationHeader("bearer token-123"),
    "token-123",
  );
});

Deno.test("bearerTokenFromAuthorizationHeader rejects missing or malformed header", () => {
  assertEquals(bearerTokenFromAuthorizationHeader(null), null);
  assertEquals(bearerTokenFromAuthorizationHeader(""), null);
  assertEquals(bearerTokenFromAuthorizationHeader("apikey token-123"), null);
  assertEquals(bearerTokenFromAuthorizationHeader("Bearer   "), null);
});

Deno.test("authFailureCode maps missing sessions to a stable code", () => {
  assertEquals(
    authFailureCode("error getting user: Auth session missing!"),
    "auth_session_missing",
  );
});

Deno.test("authFailureCode maps other failures to invalid session token", () => {
  assertEquals(authFailureCode("JWT expired"), "invalid_session_token");
  assertEquals(authFailureCode(undefined), "invalid_session_token");
});

const validClaims = {
  sub: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6",
  iss: "https://project.supabase.co/auth/v1",
  aud: "authenticated",
  exp: 2_000_000_000,
  iat: 1_900_000_000,
  role: "authenticated",
};

Deno.test("validateVerifiedClaims accepts valid anonymous authenticated claims", () => {
  const result = validateVerifiedClaims(
    { ...validClaims, is_anonymous: true },
    "https://project.supabase.co/auth/v1",
    1_950_000_000,
  );
  assertEquals(result.valid, true);
});

Deno.test("validateVerifiedClaims rejects expired claims", () => {
  const result = validateVerifiedClaims(
    { ...validClaims, exp: 1_900_000_000 },
    "https://project.supabase.co/auth/v1",
    1_950_000_000,
  );
  assertEquals(result.valid, false);
});

Deno.test("validateVerifiedClaims rejects malformed issuer, audience, and subject", () => {
  assertEquals(
    validateVerifiedClaims(
      { ...validClaims, iss: "https://attacker.invalid/auth/v1" },
      "https://project.supabase.co/auth/v1",
      1_950_000_000,
    ).valid,
    false,
  );
  assertEquals(
    validateVerifiedClaims(
      { ...validClaims, aud: "service" },
      "https://project.supabase.co/auth/v1",
      1_950_000_000,
    ).valid,
    false,
  );
  assertEquals(
    validateVerifiedClaims(
      { ...validClaims, sub: "not-a-uuid" },
      "https://project.supabase.co/auth/v1",
      1_950_000_000,
    ).valid,
    false,
  );
});

Deno.test("validateVerifiedClaims rejects service-role replay on the public auth path", () => {
  const result = validateVerifiedClaims(
    { ...validClaims, role: "service_role" },
    "https://project.supabase.co/auth/v1",
    1_950_000_000,
  );
  assertEquals(result.valid, false);
});

Deno.test("claims authentication shares the pinned SDK and remains opt-in", async () => {
  const [denoConfigSource, authSource, claimsAuthSource, edgeHandlerSource] =
    await Promise.all([
      Deno.readTextFile(new URL("../deno.json", import.meta.url)),
      Deno.readTextFile(new URL("../_shared/auth.ts", import.meta.url)),
      Deno.readTextFile(new URL("../_shared/claimsAuth.ts", import.meta.url)),
      Deno.readTextFile(new URL("../_shared/edgeHandler.ts", import.meta.url)),
    ]);
  const denoConfig = JSON.parse(denoConfigSource) as {
    imports?: Record<string, string>;
  };

  assertEquals(
    denoConfig.imports?.["@supabase/supabase-js"],
    "npm:@supabase/supabase-js@2.110.6",
  );
  assertEquals(claimsAuthSource.includes("@supabase/supabase-js"), true);
  assertEquals(authSource.includes("@supabase/supabase-js"), true);
  assertEquals(claimsAuthSource.includes("https://esm.sh"), false);
  assertEquals(authSource.includes("https://esm.sh"), false);
  assertEquals(edgeHandlerSource.includes("claimsAuth"), false);
  assertEquals(edgeHandlerSource.includes("requireClaimsAuth"), false);
});
