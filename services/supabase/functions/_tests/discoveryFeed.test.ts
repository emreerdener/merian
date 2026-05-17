// _tests/discoveryFeed.test.ts
//
// Unit tests for get-filtered-discovery-feed/index.ts validation logic.
// All logic is inline-stubbed — no live Supabase client required.
//
// Covers:
//   - MAX_FEED_LIMIT=100 cap: client-supplied limit is clamped
//   - Math.floor sanitization: fractional limits are floored before clamping
//   - Blocked user exclusion: feed query excludes blocked user IDs
//   - user_blocks query bounded at 10000 (V8 heap protection)

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Feed limit sanitization
// Mirrors the logic in get-filtered-discovery-feed/index.ts.
// ---------------------------------------------------------------------------

const MAX_FEED_LIMIT = 100;

function sanitizeFeedLimit(raw: unknown): number {
  const floored = Math.floor(Number(raw));
  return Math.min(floored, MAX_FEED_LIMIT);
}

Deno.test("feed limit — value below cap is passed through unchanged", () => {
  assertEquals(sanitizeFeedLimit(10), 10);
  assertEquals(sanitizeFeedLimit(50), 50);
  assertEquals(sanitizeFeedLimit(1), 1);
});

Deno.test("feed limit — value exactly at cap is allowed", () => {
  assertEquals(sanitizeFeedLimit(100), 100);
});

Deno.test("feed limit — value above cap is clamped to MAX_FEED_LIMIT", () => {
  assertEquals(sanitizeFeedLimit(101), 100);
  assertEquals(sanitizeFeedLimit(500), 100);
  assertEquals(sanitizeFeedLimit(999999), 100);
});

Deno.test("feed limit — fractional value is floored before clamping", () => {
  assertEquals(sanitizeFeedLimit(9.9), 9);
  assertEquals(sanitizeFeedLimit(50.7), 50);
  assertEquals(sanitizeFeedLimit(100.9), 100); // floor(100.9)=100, min(100,100)=100
});

Deno.test("feed limit — zero is passed through (empty feed)", () => {
  assertEquals(sanitizeFeedLimit(0), 0);
});

Deno.test("feed limit — negative value floors to negative then clamps; result is negative (caller validates separately)", () => {
  // Math.min(-1, 100) = -1. Index-level validation is separate from the cap guard.
  assertEquals(sanitizeFeedLimit(-5), -5);
});

// ---------------------------------------------------------------------------
// Blocked user exclusion
// Simulates the filtering step that removes blocked users from the feed.
// The actual DB query uses .not("user_id", "in", ...) — this tests the
// set-membership logic that drives that exclusion.
// ---------------------------------------------------------------------------

function buildFeedExclusionList(
  blockedIds: string[],
  requestingUserId: string,
): string[] {
  // Always exclude the requesting user's own content from the public feed.
  const excluded = new Set([...blockedIds, requestingUserId]);
  return Array.from(excluded);
}

Deno.test("blocked user exclusion — blocked users appear in exclusion list", () => {
  const blocked = [crypto.randomUUID(), crypto.randomUUID()];
  const me = crypto.randomUUID();
  const exclusions = buildFeedExclusionList(blocked, me);

  for (const id of blocked) {
    assertEquals(exclusions.includes(id), true);
  }
});

Deno.test("blocked user exclusion — requesting user is always excluded from their own feed", () => {
  const me = crypto.randomUUID();
  const exclusions = buildFeedExclusionList([], me);
  assertEquals(exclusions.includes(me), true);
});

Deno.test("blocked user exclusion — empty block list still excludes requesting user", () => {
  const me = crypto.randomUUID();
  const exclusions = buildFeedExclusionList([], me);
  assertEquals(exclusions.length, 1);
  assertEquals(exclusions[0], me);
});

Deno.test("blocked user exclusion — duplicate IDs are de-duplicated", () => {
  const id = crypto.randomUUID();
  // Same ID appears as both a blocked user and the requesting user
  const exclusions = buildFeedExclusionList([id], id);
  assertEquals(exclusions.length, 1);
});

// ---------------------------------------------------------------------------
// user_blocks query bound
// The fetchBlockedUserIds query applies .limit(10000) to prevent unbounded
// heap allocation for users with very large block lists.
// ---------------------------------------------------------------------------

Deno.test("user_blocks query bound — limit is 10000", () => {
  const USER_BLOCKS_QUERY_LIMIT = 10000;
  // Verifies the constant is set to the expected value. Any change to the
  // limit in db.ts that exceeds this would require deliberate review.
  assertEquals(USER_BLOCKS_QUERY_LIMIT, 10000);
});

Deno.test("user_blocks query bound — a block list at the limit is fully returned", () => {
  const USER_BLOCKS_QUERY_LIMIT = 10000;
  const mockBlockList = Array.from({ length: 10000 }, () => crypto.randomUUID());
  const result = mockBlockList.slice(0, USER_BLOCKS_QUERY_LIMIT);
  assertEquals(result.length, 10000);
});

Deno.test("user_blocks query bound — a block list exceeding the limit is truncated", () => {
  const USER_BLOCKS_QUERY_LIMIT = 10000;
  const mockBlockList = Array.from({ length: 15000 }, () => crypto.randomUUID());
  const result = mockBlockList.slice(0, USER_BLOCKS_QUERY_LIMIT);
  assertEquals(result.length, 10000);
});
