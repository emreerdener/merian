import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Worker-level tier cache — persists across warm isolate re-use, eliminating the DB round-trip
// for every scan after the first. TTL of 5 minutes is short enough to pick up subscription
// changes without holding stale data across a full user session.
const _tierCache = new Map<string, { tier: string; ts: number }>();
const _TIER_CACHE_TTL_MS = 5 * 60_000;

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
    .select("subscription_tier")
    .eq("id", userId)
    .maybeSingle();

  if (data) {
    const tier = data.subscription_tier as string;
    _tierCache.set(userId, { tier, ts: Date.now() });
    return tier;
  }

  // Ghost user: intentionally not cached so the background task can detect
  // the missing row and trigger the users-table upsert before the scans FK insert.
  return "free";
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
  _tierCache.set(userId, { tier, ts: Date.now() });
}
