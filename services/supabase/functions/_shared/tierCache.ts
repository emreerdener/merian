import { SupabaseClient } from "@supabase/supabase-js";

export type EffectiveTier = "free" | "pro";
export type SubscriptionTier = "free" | "pro";
export type TelemetryPlan = "free" | "pro_paid" | "pro_trial";

export interface TierResolution {
  effective_tier: EffectiveTier;
  plan: TelemetryPlan;
  subscription_tier: SubscriptionTier | null;
  trial_active: boolean;
  user_exists: boolean;
}

// Worker-level tier cache — persists across warm isolate re-use, eliminating the DB round-trip
// for every scan after the first. TTL of 5 minutes is short enough to pick up subscription
// changes without holding stale data across a full user session.
const _tierCache = new Map<
  string,
  { resolution: TierResolution; ts: number }
>();
const _TIER_CACHE_TTL_MS = 5 * 60_000;
// Hard cap: on a warm isolate serving many distinct users, the map would otherwise grow
// unboundedly. When the cap is reached, expired entries are swept first; if the map is
// still at or above 75% of the cap after the sweep, the oldest 25% of remaining entries
// are evicted to make room without discarding recently-fetched tiers.
const _TIER_CACHE_MAX_ENTRIES = 1000;

function _cacheSet(userId: string, resolution: TierResolution): void {
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
  _tierCache.set(userId, { resolution, ts: Date.now() });
}

function isTrialActive(createdAt: string | null | undefined): boolean {
  if (!createdAt) return false;
  const createdAtDate = new Date(createdAt);
  const createdAtMs = createdAtDate.getTime();
  if (!Number.isFinite(createdAtMs)) return false;
  const diffMs = Date.now() - createdAtMs;
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  return diffDays <= 7;
}

function isTimestampInFuture(value: string | null | undefined): boolean {
  if (!value) return false;
  const date = new Date(value);
  const time = date.getTime();
  return Number.isFinite(time) && time > Date.now();
}

export function resolutionForUserRow(row: {
  subscription_tier?: string | null;
  created_at?: string | null;
  subscription_expires_at?: string | null;
}): TierResolution {
  const subscriptionTier: SubscriptionTier = row.subscription_tier === "pro"
    ? "pro"
    : "free";

  if (subscriptionTier === "pro") {
    if (
      row.subscription_expires_at &&
      !isTimestampInFuture(row.subscription_expires_at)
    ) {
      return {
        effective_tier: "free",
        plan: "free",
        subscription_tier: "free",
        trial_active: false,
        user_exists: true,
      };
    }

    return {
      effective_tier: "pro",
      plan: "pro_paid",
      subscription_tier: "pro",
      trial_active: false,
      user_exists: true,
    };
  }

  const trialActive = isTrialActive(row.created_at);
  return {
    effective_tier: trialActive ? "pro" : "free",
    plan: trialActive ? "pro_trial" : "free",
    subscription_tier: "free",
    trial_active: trialActive,
    user_exists: true,
  };
}

function ghostTrialResolution(): TierResolution {
  return {
    effective_tier: "pro",
    plan: "pro_trial",
    subscription_tier: null,
    trial_active: true,
    user_exists: false,
  };
}

export function tierTelemetryProperties(
  resolution: TierResolution,
): Record<string, unknown> {
  return {
    plan: resolution.plan,
    effective_tier: resolution.effective_tier,
    subscription_tier: resolution.subscription_tier,
    trial_active: resolution.trial_active,
  };
}

/**
 * Returns the effective tier and telemetry plan for the given user ID, using a
 * worker-level in-memory cache with a 5-minute TTL to eliminate redundant DB
 * round-trips.
 *
 * Ghost users who are not yet in the `users` table are treated as trial Pro
 * and cached with `user_exists = false`; the background ingestion path uses
 * that flag to create the FK row before inserting the scan.
 */
export async function resolveTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<TierResolution> {
  const cached = _tierCache.get(userId);
  if (cached && Date.now() - cached.ts < _TIER_CACHE_TTL_MS) {
    return cached.resolution;
  }

  const { data } = await supabaseAdmin
    .from("users")
    .select("subscription_tier, created_at, subscription_expires_at")
    .eq("id", userId)
    .maybeSingle();

  if (data) {
    const resolution = resolutionForUserRow(data);
    _cacheSet(userId, resolution);
    return resolution;
  }

  // Ghost user: brand new and implicitly within the 7-day trial.
  const resolution = ghostTrialResolution();
  _cacheSet(userId, resolution);
  return resolution;
}

/**
 * Compatibility wrapper for older call sites that only need model/storage tier.
 */
export async function getTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<EffectiveTier> {
  return (await resolveTierForUser(userId, supabaseAdmin)).effective_tier;
}

/**
 * Returns true if the tier for `userId` is already in the cache and not expired.
 *
 * Used by older tests and call sites to check whether a fresh tier resolution
 * is present. Ghost users are cached too; use `getCachedTierResolution()` when
 * the caller needs to know whether the backing user row exists.
 */
export function hasTierCached(userId: string): boolean {
  const cached = _tierCache.get(userId);
  return !!(cached && Date.now() - cached.ts < _TIER_CACHE_TTL_MS);
}

export function getCachedTierResolution(
  userId: string,
): TierResolution | null {
  const cached = _tierCache.get(userId);
  if (!cached || Date.now() - cached.ts >= _TIER_CACHE_TTL_MS) return null;
  return cached.resolution;
}

/**
 * Explicitly writes a tier entry into the cache.
 *
 * Called by `identify`'s background task after upserting a ghost user into
 * the `users` table, so subsequent warm-isolate requests skip the DB round-trip.
 */
export function setTierCache(userId: string, tier: string): void {
  _cacheSet(
    userId,
    tier === "pro"
      ? {
        effective_tier: "pro",
        plan: "pro_paid",
        subscription_tier: "pro",
        trial_active: false,
        user_exists: true,
      }
      : {
        effective_tier: "free",
        plan: "free",
        subscription_tier: "free",
        trial_active: false,
        user_exists: true,
      },
  );
}

export function setTierResolutionCache(
  userId: string,
  resolution: TierResolution,
): void {
  _cacheSet(userId, resolution);
}
