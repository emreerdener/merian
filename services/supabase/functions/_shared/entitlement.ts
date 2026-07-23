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
  entitlement_version: number;
}

function isTrialActive(createdAt: string | null | undefined): boolean {
  if (!createdAt) return false;
  const createdAtDate = new Date(createdAt);
  const createdAtMs = createdAtDate.getTime();
  if (!Number.isFinite(createdAtMs)) return false;
  const diffMs = Date.now() - createdAtMs;
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  return diffDays >= 0 && diffDays <= 7;
}

function isTimestampInFuture(value: string | null | undefined): boolean {
  if (!value) return false;
  const date = new Date(value);
  const time = date.getTime();
  return Number.isFinite(time) && time > Date.now();
}

function isValidTimestamp(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    Number.isFinite(new Date(value).getTime());
}

export function resolutionForUserRow(row: {
  subscription_tier?: string | null;
  created_at?: string | null;
  subscription_expires_at?: string | null;
  entitlement_version?: number | null;
}): TierResolution {
  if (
    (row.subscription_tier !== "free" &&
      row.subscription_tier !== "pro") ||
    !isValidTimestamp(row.created_at) ||
    (row.subscription_expires_at !== null &&
      row.subscription_expires_at !== undefined &&
      !isValidTimestamp(row.subscription_expires_at)) ||
    typeof row.entitlement_version !== "number" ||
    !Number.isSafeInteger(row.entitlement_version) ||
    row.entitlement_version <= 0
  ) {
    throw entitlementUnavailable();
  }

  const subscriptionTier: SubscriptionTier = row.subscription_tier;
  const entitlementVersion = row.entitlement_version;

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
        entitlement_version: entitlementVersion,
      };
    }

    return {
      effective_tier: "pro",
      plan: "pro_paid",
      subscription_tier: "pro",
      trial_active: false,
      user_exists: true,
      entitlement_version: entitlementVersion,
    };
  }

  const trialActive = isTrialActive(row.created_at);
  return {
    effective_tier: trialActive ? "pro" : "free",
    plan: trialActive ? "pro_trial" : "free",
    subscription_tier: "free",
    trial_active: trialActive,
    user_exists: true,
    entitlement_version: entitlementVersion,
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
    entitlement_version: resolution.entitlement_version,
  };
}

function entitlementUnavailable(): Error & { status: number; code: string } {
  const error = new Error(
    "AI entitlement could not be verified. Please try again.",
  ) as Error & { status: number; code: string };
  error.status = 503;
  error.code = "ai_entitlement_unavailable";
  return error;
}

/**
 * Resolves the current entitlement from the durable database row.
 *
 * This intentionally performs a database read on every non-quota call. An Edge
 * isolate's memory is not a coherent entitlement store, and a missing row or a
 * query error must never be interpreted as Pro access.
 */
export async function resolveTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<TierResolution> {
  try {
    const { data, error } = await supabaseAdmin
      .from("users")
      .select(
        "subscription_tier, created_at, subscription_expires_at, entitlement_version",
      )
      .eq("id", userId)
      .abortSignal(AbortSignal.timeout(5_000))
      .maybeSingle();

    if (error || !data) throw entitlementUnavailable();
    return resolutionForUserRow(data);
  } catch (error) {
    if (
      error instanceof Error &&
      "code" in error &&
      error.code === "ai_entitlement_unavailable"
    ) {
      throw error;
    }
    throw entitlementUnavailable();
  }
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
