// _tests/validation.test.ts
//
// Unit tests for shared input validation patterns used across Edge Functions.
// All logic is inline-stubbed — no live Supabase client required.
//
// Covers:
//   - UUID format validation (block-user, flag-issue)
//   - Self-block guard (block-user)
//   - flagReason enum guard (flag-issue)
//   - exportScope enum guard + includePreciseCoordinates type check (request-export-dwca)
//   - atomic export-request disposition validation (request-export-dwca/db.ts)

import { assert, assertEquals } from "@std/assert";

// ---------------------------------------------------------------------------
// UUID format validation
// Mirrors the UUID_RE guard in block-user/index.ts and flag-issue/index.ts.
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(v: unknown): boolean {
  return typeof v === "string" && UUID_RE.test(v);
}

Deno.test("UUID validation — well-formed lowercase UUID passes", () => {
  assert(isValidUuid("550e8400-e29b-41d4-a716-446655440000"));
});

Deno.test("UUID validation — well-formed uppercase UUID passes (case-insensitive)", () => {
  assert(isValidUuid("550E8400-E29B-41D4-A716-446655440000"));
});

Deno.test("UUID validation — crypto.randomUUID() output always passes", () => {
  for (let i = 0; i < 10; i++) {
    assert(
      isValidUuid(crypto.randomUUID()),
      "crypto.randomUUID() must pass validation",
    );
  }
});

Deno.test("UUID validation — plain string without hyphens is rejected", () => {
  assertEquals(isValidUuid("550e8400e29b41d4a716446655440000"), false);
});

Deno.test("UUID validation — empty string is rejected", () => {
  assertEquals(isValidUuid(""), false);
});

Deno.test("UUID validation — SQL injection attempt is rejected", () => {
  assertEquals(isValidUuid("' OR 1=1 --"), false);
});

Deno.test("UUID validation — null is rejected", () => {
  assertEquals(isValidUuid(null), false);
});

Deno.test("UUID validation — number is rejected", () => {
  assertEquals(isValidUuid(12345), false);
});

Deno.test("UUID validation — UUID with wrong segment lengths is rejected", () => {
  assertEquals(isValidUuid("550e8400-e29b-41d4-a716-44665544000"), false); // short last segment
  assertEquals(isValidUuid("550e8400-e29b-41d4-a716-4466554400000"), false); // long last segment
});

// ---------------------------------------------------------------------------
// Self-block guard (block-user/index.ts)
// ---------------------------------------------------------------------------

function isSelfBlock(requestingUserId: string, blockedId: string): boolean {
  return blockedId === requestingUserId;
}

Deno.test("self-block guard — same ID triggers guard", () => {
  const id = crypto.randomUUID();
  assert(isSelfBlock(id, id));
});

Deno.test("self-block guard — different IDs do not trigger guard", () => {
  assertEquals(isSelfBlock(crypto.randomUUID(), crypto.randomUUID()), false);
});

// ---------------------------------------------------------------------------
// flagReason enum validation (flag-issue/index.ts)
// ---------------------------------------------------------------------------

const VALID_FLAG_REASONS = new Set([
  "Incorrect species",
  "Inappropriate content",
  "Bad image quality",
  "Other",
]);

function isValidFlagReason(v: unknown): boolean {
  return typeof v === "string" && VALID_FLAG_REASONS.has(v);
}

Deno.test("flagReason — all documented enum values are accepted", () => {
  assert(isValidFlagReason("Incorrect species"));
  assert(isValidFlagReason("Inappropriate content"));
  assert(isValidFlagReason("Bad image quality"));
  assert(isValidFlagReason("Other"));
});

Deno.test("flagReason — arbitrary string is rejected", () => {
  assertEquals(isValidFlagReason("wrong"), false);
  assertEquals(isValidFlagReason("incorrect species"), false); // case-sensitive
  assertEquals(isValidFlagReason(""), false);
});

Deno.test("flagReason — null and non-string are rejected", () => {
  assertEquals(isValidFlagReason(null), false);
  assertEquals(isValidFlagReason(42), false);
});

// ---------------------------------------------------------------------------
// exportScope enum validation (request-export-dwca/index.ts)
// ---------------------------------------------------------------------------

const VALID_EXPORT_SCOPES = new Set(["personal"]);

function isValidExportScope(v: unknown): boolean {
  return typeof v === "string" && VALID_EXPORT_SCOPES.has(v);
}

Deno.test("exportScope — 'personal' is accepted", () => {
  assert(isValidExportScope("personal"));
});

Deno.test("exportScope — 'global' is reserved for internal administration", () => {
  assertEquals(isValidExportScope("global"), false);
});

Deno.test("exportScope — old value 'user' is rejected (renamed to 'personal')", () => {
  // Default was changed from "user" to "personal" — ensure old value is not silently accepted.
  assertEquals(isValidExportScope("user"), false);
});

Deno.test("exportScope — arbitrary value is rejected", () => {
  assertEquals(isValidExportScope("all"), false);
  assertEquals(isValidExportScope(""), false);
});

Deno.test("exportScope — null is rejected", () => {
  assertEquals(isValidExportScope(null), false);
});

// ---------------------------------------------------------------------------
// includePreciseCoordinates type validation (request-export-dwca/index.ts)
// ---------------------------------------------------------------------------

function isValidBooleanFlag(v: unknown): boolean {
  return typeof v === "boolean";
}

Deno.test("includePreciseCoordinates — true is accepted", () => {
  assert(isValidBooleanFlag(true));
});

Deno.test("includePreciseCoordinates — false is accepted", () => {
  assert(isValidBooleanFlag(false));
});

Deno.test("includePreciseCoordinates — string 'true' is rejected (strict boolean required)", () => {
  assertEquals(isValidBooleanFlag("true"), false);
  assertEquals(isValidBooleanFlag("false"), false);
});

Deno.test("includePreciseCoordinates — number 1/0 is rejected", () => {
  assertEquals(isValidBooleanFlag(1), false);
  assertEquals(isValidBooleanFlag(0), false);
});

Deno.test("includePreciseCoordinates — null is rejected", () => {
  assertEquals(isValidBooleanFlag(null), false);
});

// ---------------------------------------------------------------------------
// Atomic export-request disposition validation (request-export-dwca/db.ts)
// ---------------------------------------------------------------------------

const VALID_EXPORT_REQUEST_DISPOSITIONS = new Set([
  "queued",
  "disabled",
  "rate_limited",
  "already_pending",
]);

function isValidExportRequestDisposition(value: unknown): boolean {
  return typeof value === "string" &&
    VALID_EXPORT_REQUEST_DISPOSITIONS.has(value);
}

Deno.test("export request — every stable database disposition is accepted", () => {
  assert(isValidExportRequestDisposition("queued"));
  assert(isValidExportRequestDisposition("disabled"));
  assert(isValidExportRequestDisposition("rate_limited"));
  assert(isValidExportRequestDisposition("already_pending"));
});

Deno.test("export request — unknown and malformed dispositions are rejected", () => {
  assertEquals(isValidExportRequestDisposition("enabled"), false);
  assertEquals(isValidExportRequestDisposition(""), false);
  assertEquals(isValidExportRequestDisposition(null), false);
});
