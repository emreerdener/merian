// services/supabase/functions/revenuecat-webhook/index_test.ts
//
// Tests for the UUID validation guard added to index.ts.
//
// Context: RevenueCat can send anonymous IDs ("$RCAnonymousID:xxx") for
// un-linked purchases.  A plain falsy check passes these strings, but they
// fail PostgreSQL UUID constraints and produce confusing 500 errors.
// The guard validates `app_user_id` against a strict UUID regex and returns
// HTTP 400 before any DB access.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SEVEN_DAY_PASS_PRODUCT_ID } from "../_shared/subscriptionPass.ts";
import { classifyRevenueCatEvent } from "./events.ts";

// ---------------------------------------------------------------------------
// UUID regex — inlined from index.ts so the tests remain self-contained.
// If the production regex changes, update this copy too.
// ---------------------------------------------------------------------------
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value: unknown): boolean {
  return typeof value === "string" && UUID_REGEX.test(value);
}

// ---------------------------------------------------------------------------
// Should reject
// ---------------------------------------------------------------------------

Deno.test("UUID validation rejects RevenueCat anonymous ID ($RCAnonymousID:xxx)", () => {
  assertEquals(
    isValidUuid("$RCAnonymousID:abc123def456"),
    false,
    "$RCAnonymousID format must be rejected — it would fail PostgreSQL UUID constraints",
  );
});

Deno.test("UUID validation rejects plain non-UUID string", () => {
  assertEquals(isValidUuid("not-a-uuid"), false);
});

Deno.test("UUID validation rejects empty string", () => {
  assertEquals(isValidUuid(""), false);
});

Deno.test("UUID validation rejects null", () => {
  assertEquals(isValidUuid(null), false);
});

Deno.test("UUID validation rejects undefined", () => {
  assertEquals(isValidUuid(undefined), false);
});

Deno.test("UUID validation rejects numeric type", () => {
  assertEquals(isValidUuid(12345), false);
});

Deno.test("UUID validation rejects UUID with missing hyphens", () => {
  assertEquals(isValidUuid("550e8400e29b41d4a716446655440000"), false);
});

Deno.test("UUID validation rejects UUID with wrong segment lengths", () => {
  assertEquals(
    isValidUuid("550e8400-e29b-41d4-a716-44665544000"),
    false,
    "Short UUID must be rejected",
  );
  assertEquals(
    isValidUuid("550e8400-e29b-41d4-a716-4466554400000"),
    false,
    "Long UUID must be rejected",
  );
});

// ---------------------------------------------------------------------------
// Should accept
// ---------------------------------------------------------------------------

Deno.test("UUID validation accepts a lowercase v4 UUID", () => {
  assertEquals(
    isValidUuid("550e8400-e29b-41d4-a716-446655440000"),
    true,
    "Valid lowercase v4 UUID must pass",
  );
});

Deno.test("UUID validation accepts an uppercase UUID", () => {
  assertEquals(
    isValidUuid("550E8400-E29B-41D4-A716-446655440000"),
    true,
    "Valid uppercase UUID must pass — regex is case-insensitive",
  );
});

Deno.test("UUID validation accepts a freshly generated crypto.randomUUID()", () => {
  const id = crypto.randomUUID();
  assertEquals(
    isValidUuid(id),
    true,
    `crypto.randomUUID() output "${id}" must always pass the UUID guard`,
  );
});

Deno.test("UUID validation accepts Supabase-style lowercase UUID", () => {
  // Supabase GoTrue emits UUIDs in lowercase — this is the format we receive in JWTs.
  assertEquals(
    isValidUuid("a1b2c3d4-e5f6-7890-abcd-ef1234567890"),
    true,
  );
});

Deno.test("classifyRevenueCatEvent: exact 7-day pass grants timed pro", () => {
  const purchasedAtMs = Date.parse("2026-06-16T12:00:00.000Z");
  const action = classifyRevenueCatEvent({
    type: "NON_RENEWING_PURCHASE",
    product_id: SEVEN_DAY_PASS_PRODUCT_ID,
    purchased_at_ms: purchasedAtMs,
  });

  assertEquals(action?.targetTier, "pro");
  assertEquals(action?.expiresAt, "2026-06-23T12:00:00.000Z");
  assertEquals(action?.storageMigration, "free_to_pro");
});

Deno.test("classifyRevenueCatEvent: unrelated non-renewing purchase is ignored", () => {
  const action = classifyRevenueCatEvent({
    type: "NON_RENEWING_PURCHASE",
    product_id: "some_other_non_renewing_product",
    purchased_at_ms: Date.now(),
  });

  assertEquals(action, null);
});

Deno.test("classifyRevenueCatEvent: standard subscription purchase clears expiry", () => {
  const action = classifyRevenueCatEvent({
    type: "INITIAL_PURCHASE",
    product_id: "merian_pro_monthly",
  });

  assertEquals(action?.targetTier, "pro");
  assertEquals(action?.expiresAt, null);
  assertEquals(action?.storageMigration, "free_to_pro");
});

Deno.test("classifyRevenueCatEvent: pass refund downgrades immediately", () => {
  const action = classifyRevenueCatEvent({
    type: "REFUND",
    product_id: SEVEN_DAY_PASS_PRODUCT_ID,
  });

  assertEquals(action?.targetTier, "free");
  assertEquals(action?.expiresAt, null);
  assertEquals(action?.storageMigration, "pro_to_free");
});
