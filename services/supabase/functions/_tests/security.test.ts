import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { timingSafeCompare } from "../_shared/http.ts";

Deno.test("timingSafeCompare — equal strings return true", () => {
  assertEquals(timingSafeCompare("abc123", "abc123"), true);
});

Deno.test("timingSafeCompare — empty strings are equal", () => {
  assertEquals(timingSafeCompare("", ""), true);
});

Deno.test("timingSafeCompare — different strings return false", () => {
  assertEquals(timingSafeCompare("abc123", "xyz456"), false);
});

Deno.test("timingSafeCompare — different lengths return false without leaking length via exception", () => {
  assertEquals(timingSafeCompare("short", "longer-string"), false);
  assertEquals(timingSafeCompare("longer-string", "short"), false);
});

Deno.test("timingSafeCompare — single character difference returns false", () => {
  assertEquals(timingSafeCompare("secret1", "secret2"), false);
});

Deno.test("timingSafeCompare — Bearer token format used in webhooks", () => {
  const secret = "my-webhook-secret-abc123";
  assertEquals(timingSafeCompare(`Bearer ${secret}`, `Bearer ${secret}`), true);
  assertEquals(
    timingSafeCompare(`Bearer ${secret}`, `Bearer wrong-secret`),
    false,
  );
  assertEquals(timingSafeCompare(`Bearer ${secret}`, secret), false);
});

Deno.test("timingSafeCompare — unicode strings compared byte-by-byte", () => {
  assertEquals(timingSafeCompare("café", "café"), true);
  assertEquals(timingSafeCompare("café", "cafe"), false);
});
