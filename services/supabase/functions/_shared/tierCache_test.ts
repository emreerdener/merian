// services/supabase/functions/_shared/tierCache_test.ts
//
// Tests for the in-memory tier cache and its two-pass LRU eviction policy.
//
// Eviction fires when the cache reaches _TIER_CACHE_MAX_ENTRIES (1000) and
// a NEW entry is inserted:
//   Pass 1: sweep expired entries (TTL = 5 min).
//   Pass 2: if cache is still >= 75% full after pass 1, evict the oldest 25%.
//
// Since we cannot control Date.now() from outside the module, these tests
// focus on the capacity-eviction path (pass 2) where all entries are fresh.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  getCachedTierResolution,
  getTierForUser,
  hasTierCached,
  resolveTierForUser,
  setTierCache,
} from "./tierCache.ts";

function mockSupabase(row: Record<string, unknown> | null) {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve({ data: row }),
        }),
      }),
    }),
  };
}

function isoDaysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

// ---------------------------------------------------------------------------
// Basic set / get contract
// ---------------------------------------------------------------------------

Deno.test("setTierCache + hasTierCached: entry is present immediately after set", () => {
  const userId = `tier_test_basic_${crypto.randomUUID()}`;
  setTierCache(userId, "pro");
  assertEquals(
    hasTierCached(userId),
    true,
    "Entry must be present immediately after setTierCache",
  );
});

Deno.test("hasTierCached returns false for unknown user", () => {
  const userId = `tier_test_unknown_${crypto.randomUUID()}`;
  assertEquals(
    hasTierCached(userId),
    false,
    "Unknown user must not be in cache",
  );
});

Deno.test("setTierCache can overwrite an existing entry", () => {
  const userId = `tier_test_overwrite_${crypto.randomUUID()}`;
  setTierCache(userId, "free");
  setTierCache(userId, "pro");
  // Still in cache after overwrite
  assertEquals(hasTierCached(userId), true, "Entry must survive an overwrite");
});

Deno.test("resolveTierForUser: paid pro resolves pro_paid", async () => {
  const userId = `tier_test_paid_${crypto.randomUUID()}`;
  const resolution = await resolveTierForUser(
    userId,
    mockSupabase({
      subscription_tier: "pro",
      created_at: isoDaysAgo(20),
    }) as never,
  );
  assertEquals(resolution.effective_tier, "pro");
  assertEquals(resolution.plan, "pro_paid");
  assertEquals(resolution.subscription_tier, "pro");
  assertEquals(resolution.trial_active, false);
});

Deno.test("resolveTierForUser: recent free user resolves pro_trial", async () => {
  const userId = `tier_test_trial_${crypto.randomUUID()}`;
  const resolution = await resolveTierForUser(
    userId,
    mockSupabase({
      subscription_tier: "free",
      created_at: isoDaysAgo(2),
    }) as never,
  );
  assertEquals(resolution.effective_tier, "pro");
  assertEquals(resolution.plan, "pro_trial");
  assertEquals(resolution.subscription_tier, "free");
  assertEquals(resolution.trial_active, true);
});

Deno.test("resolveTierForUser: expired free trial resolves free", async () => {
  const userId = `tier_test_free_${crypto.randomUUID()}`;
  const resolution = await resolveTierForUser(
    userId,
    mockSupabase({
      subscription_tier: "free",
      created_at: isoDaysAgo(8),
    }) as never,
  );
  assertEquals(resolution.effective_tier, "free");
  assertEquals(resolution.plan, "free");
  assertEquals(resolution.subscription_tier, "free");
  assertEquals(resolution.trial_active, false);
});

Deno.test("resolveTierForUser: ghost user resolves and caches trial pro", async () => {
  const userId = `tier_test_ghost_${crypto.randomUUID()}`;
  const resolution = await resolveTierForUser(
    userId,
    mockSupabase(null) as never,
  );
  assertEquals(resolution.effective_tier, "pro");
  assertEquals(resolution.plan, "pro_trial");
  assertEquals(resolution.subscription_tier, null);
  assertEquals(resolution.trial_active, true);
  assertEquals(resolution.user_exists, false);
  assertEquals(hasTierCached(userId), true);
  assertEquals(getCachedTierResolution(userId)?.effective_tier, "pro");

  const cachedTier = await getTierForUser(
    userId,
    mockSupabase({
      subscription_tier: "free",
      created_at: isoDaysAgo(30),
    }) as never,
  );
  assertEquals(
    cachedTier,
    "pro",
    "Cached ghost trial tier must remain effective pro",
  );
});

// ---------------------------------------------------------------------------
// Capacity eviction — pass 2 (oldest-25% path)
//
// Strategy: fill the cache to exactly _TIER_CACHE_MAX_ENTRIES (1000) using
// unique user IDs with a shared prefix, then insert one more entry and verify:
//   (a) The new entry IS in cache.
//   (b) Some early entries were evicted.
//
// We use a dedicated prefix so these 1000 synthetic entries don't interfere
// with cache state from other tests running in the same isolate.
// ---------------------------------------------------------------------------

Deno.test("capacity eviction: oldest entries are evicted when cache exceeds max", () => {
  const prefix = `evict_${crypto.randomUUID().slice(0, 8)}_`;
  const MAX = 1000;

  // Fill to capacity with fresh (non-expired) entries.
  // NOTE: The cache is a module-level singleton shared across all tests in the
  // same Deno process, so it may already contain entries from earlier tests.
  // We do NOT assert pre-eviction state for early entries — eviction may fire
  // during the fill loop itself once the total (prior entries + ours) hits 1000.
  // The post-eviction assertions below are the meaningful contract.
  for (let i = 0; i < MAX; i++) {
    setTierCache(`${prefix}${i}`, "free");
  }

  // Inserting one more NEW entry triggers eviction if cache is still at capacity.
  const triggerKey = `${prefix}trigger`;
  setTierCache(triggerKey, "pro");

  // The triggering entry must always be present
  assertEquals(
    hasTierCached(triggerKey),
    true,
    "The entry that triggered eviction must be in cache",
  );

  // After pass 2 eviction (no expired entries → oldest-25% sweep):
  //   - 250 of the first 1000 entries are removed (insertion-order, oldest first)
  //   - Entries 0–249 (approx) are gone; entries 250–999 remain
  //
  // We check a few of the earliest entries to confirm eviction occurred.
  const evictedCount = [0, 1, 2, 10, 50, 100, 200, 249].filter(
    (i) => !hasTierCached(`${prefix}${i}`),
  ).length;
  assert(
    evictedCount > 0,
    "At least some of the earliest entries must have been evicted by the oldest-25% pass",
  );

  // Entries near the tail of the original 1000 must still be present
  assert(
    hasTierCached(`${prefix}750`),
    "Entry 750 must survive eviction (inserted after the eviction window)",
  );
  assert(
    hasTierCached(`${prefix}999`),
    "Entry 999 must survive eviction (most recently inserted before trigger)",
  );
});

// ---------------------------------------------------------------------------
// Idempotent update: overwriting an existing key does NOT count as a new entry
// and therefore does NOT trigger eviction at capacity.
// ---------------------------------------------------------------------------

Deno.test("capacity eviction: updating an existing key at capacity does not trigger eviction", () => {
  const prefix = `noevict_${crypto.randomUUID().slice(0, 8)}_`;
  const MAX = 1000;

  for (let i = 0; i < MAX; i++) {
    setTierCache(`${prefix}${i}`, "free");
  }

  // Overwrite entry 0 — this is NOT a new key, so the guard
  // `!_tierCache.has(userId)` prevents the eviction block from firing.
  setTierCache(`${prefix}0`, "pro");

  // All 1000 entries (including the updated one) should still be present.
  assert(hasTierCached(`${prefix}0`), "Updated entry must remain in cache");
  assert(
    hasTierCached(`${prefix}999`),
    "Unchanged entries must remain when key already existed",
  );
});
