import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bearerTokenFromAuthorizationHeader } from "../_shared/auth.ts";

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
