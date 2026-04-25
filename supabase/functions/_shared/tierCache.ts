import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Worker-level tier cache — persists across warm isolate re-use, eliminating the DB round-trip
// for every scan after the first. TTL of 5 minutes is short enough to pick up subscription
// changes without holding stale data across a full user session.
const _tierCache = new Map<string, { tier: string; ts: number }>();
const _TIER_CACHE_TTL_MS = 5 * 60_000;
// Hard cap: on a warm isolate serving many distinct users, the map would otherwise grow
// unboundedly. When the cap is reached, expired entries are swept first; if the map is
// still at or above 75% of the cap after the sweep, the oldest 25% of remaining entries
// are evicted to make room without discarding recently-fetched tiers.
const _TIER_CACHE_MAX_ENTRIES = 1000;

function _cacheSet(userId: string, tier: string): void {
  if (_tierCache.size >= _TIER_CACHE_MAX_ENTRIES && !_tierCache.has(userId)) {
    // Pass 1: sweep expired entries (cheapest eviction — no valid data lost).
    const now = Date.now();
    for (const [key, value] of _tierCache) {
      if (now - value.ts >= _TIER_CACHE_TTL_MS) _tierCache.delete(key);
    }
    // Pass 2: if still at or above 75%, evict the oldest 25% of remaining entries.
    if (_tierCache.size >= Math.ceil(_TIER_CACHE_MAX_ENTRIES * 0.75)) {
      const evictCount = Math.ceil(_tierCache.size * 0.25);
      let evicted = 0;
      for (const key of _tierCache.keys()) {
        if (evicted >= evictCount) break;
        _tierCache.delete(key);
        evicted++;
      }
    }
  }
  _tierCache.set(userId, { tier, ts: Date.now() });
}

/**
 * Returns the subscription tier for the given user ID, using a worker-level
 * in-memory cache with a 5-minute TTL to eliminate redundant DB round-trips.
 *
 * Ghost users who are not yet in the `users` table default to `"free"` but
 * are intentionally NOT cached, so the background task can detect them via
 * `hasTierCached` and trigger the ghost-user upsert.
 */
export async function getTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string> {
  const cached = _tierCache.get(userId);
  if (cached && Date.now() - cached.ts < _TIER_CACHE_TTL_MS) {
    return cached.tier;
  }

  const { data } = await supabaseAdmin
    .from("users")
    .select("subscription_tier, created_at")
    .eq("id", userId)
    .maybeSingle();

  if (data) {
    let tier = data.subscription_tier as string;
    
    if (tier !== "pro" && data.created_at) {
      const createdAtDate = new Date(data.created_at);
      const diffMs = Date.now() - createdAtDate.getTime();
      const diffDays = diffMs / (1000 * 60 * 60 * 24);
      if (diffDays <= 7) {
        tier = "pro";
      }
    }

    _cacheSet(userId, tier);
    return tier;
  }

  // Ghost user: intentionally not cached so the background task can detect
  // the missing row and trigger the users-table upsert before the scans FK insert.
  // We return "pro" because a ghost user is brand new and implicitly within the 7-day trial.
  return "pro";
}

/**
 * Returns true if the tier for `userId` is already in the cache and not expired.
 *
 * Used by `identify`'s background task: if the critical-path `getTierForUser`
 * call did NOT cache (because the user has no row in the `users` table), this
 * returns false, signalling that a ghost-user upsert is needed.
 */
export function hasTierCached(userId: string): boolean {
  const cached = _tierCache.get(userId);
  return !!(cached && Date.now() - cached.ts < _TIER_CACHE_TTL_MS);
}

/**
 * Explicitly writes a tier entry into the cache.
 *
 * Called by `identify`'s background task after upserting a ghost user into
 * the `users` table, so subsequent warm-isolate requests skip the DB round-trip.
 */
export function setTierCache(userId: string, tier: string): void {
  _cacheSet(userId, tier);
}
