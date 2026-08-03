import { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse, PublicHttpError, publicHttpError } from "./http.ts";

export const ENTITLEMENT_PROTOCOL_HEADER = "X-Merian-Entitlement-Protocol";
export const CURRENT_ENTITLEMENT_PROTOCOL = 3;

export type EffectiveTier = "free" | "pro";
export type SubscriptionTier = "free" | "pro";
export type TelemetryPlan =
  | "free"
  | "pro_paid"
  | "pro_complimentary"
  | "pro_trial";

export interface EntitlementSnapshot {
  current_plan: TelemetryPlan;
  current_tier: EffectiveTier;
  is_paid: boolean;
  scans_remaining: number;
  scans_available_to_start: number;
  in_flight_count: number;
  entitlement_version: number;
}

interface EntitlementRolloutSnapshot {
  entitlement_mode: "legacy_trial" | "complimentary";
  required_client_protocol: number;
  mode_version: number;
}

export interface TierResolution extends EntitlementSnapshot {
  effective_tier: EffectiveTier;
  plan: TelemetryPlan;
  subscription_tier: SubscriptionTier;
  trial_active: boolean;
  user_exists: true;
}

function validNonnegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

export function resolutionForEntitlementRow(
  row: Record<string, unknown>,
): TierResolution {
  const plan = row.current_plan;
  const tier = row.current_tier;
  if (
    (plan !== "free" && plan !== "pro_paid" &&
      plan !== "pro_complimentary" && plan !== "pro_trial") ||
    (tier !== "free" && tier !== "pro") ||
    typeof row.is_paid !== "boolean" ||
    !validNonnegativeInteger(row.scans_remaining) ||
    !validNonnegativeInteger(row.scans_available_to_start) ||
    !validNonnegativeInteger(row.in_flight_count) ||
    typeof row.entitlement_version !== "number" ||
    !Number.isSafeInteger(row.entitlement_version) ||
    row.entitlement_version < 1 ||
    row.scans_remaining > 3 ||
    row.scans_available_to_start > row.scans_remaining ||
    row.scans_available_to_start + row.in_flight_count !==
      row.scans_remaining ||
    (plan === "free" && tier !== "free") ||
    (plan !== "free" && tier !== "pro") ||
    (plan === "pro_paid") !== row.is_paid
  ) {
    throw entitlementUnavailable();
  }

  return {
    current_plan: plan,
    current_tier: tier,
    is_paid: row.is_paid,
    scans_remaining: row.scans_remaining,
    scans_available_to_start: row.scans_available_to_start,
    in_flight_count: row.in_flight_count,
    entitlement_version: row.entitlement_version,
    effective_tier: tier,
    plan,
    subscription_tier: row.is_paid ? "pro" : "free",
    trial_active: plan === "pro_trial",
    user_exists: true,
  };
}

export function tierTelemetryProperties(
  resolution: TierResolution,
): Record<string, unknown> {
  return {
    plan: resolution.plan,
    effective_tier: resolution.effective_tier,
    subscription_tier: resolution.subscription_tier,
    paid_status: resolution.is_paid,
    trial_active: resolution.trial_active,
    complimentary_scans_remaining: resolution.scans_remaining,
    complimentary_scans_available_to_start: resolution.scans_available_to_start,
    complimentary_scans_in_flight: resolution.in_flight_count,
    entitlement_version: resolution.entitlement_version,
  };
}

function entitlementUnavailable(): PublicHttpError {
  return publicHttpError(
    503,
    "AI entitlement could not be verified. Please try again.",
    "ai_entitlement_unavailable",
  );
}

function singleEntitlementRow(data: unknown): Record<string, unknown> | null {
  if (Array.isArray(data) && data.length !== 1) return null;
  const value = Array.isArray(data) ? data[0] : data;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

/**
 * Resolves every functional entitlement from the private database ledger.
 * Edge isolates and account creation timestamps are never authoritative.
 */
export async function resolveTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<TierResolution> {
  try {
    const { data, error } = await supabaseAdmin.rpc(
      "get_user_entitlement_service",
      { p_user_id: userId },
    ).abortSignal(AbortSignal.timeout(5_000));

    const row = singleEntitlementRow(data);
    if (error || !row) throw entitlementUnavailable();
    return resolutionForEntitlementRow(row);
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

export async function getTierForUser(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<EffectiveTier> {
  return (await resolveTierForUser(userId, supabaseAdmin)).effective_tier;
}

export function entitlementProtocolFromRequest(req: Request): number | null {
  const raw = req.headers.get(ENTITLEMENT_PROTOCOL_HEADER)?.trim();
  if (!raw || !/^[1-9][0-9]{0,2}$/.test(raw)) return null;
  const value = Number(raw);
  return Number.isSafeInteger(value) ? value : null;
}

function rolloutForRow(
  row: Record<string, unknown>,
): EntitlementRolloutSnapshot {
  const mode = row.entitlement_mode;
  const protocol = row.required_client_protocol;
  const version = row.mode_version;
  if (
    (mode !== "legacy_trial" && mode !== "complimentary") ||
    !validNonnegativeInteger(protocol) ||
    typeof version !== "number" ||
    !Number.isSafeInteger(version) ||
    version < 1 ||
    (mode === "legacy_trial" && protocol !== 0) ||
    (mode === "complimentary" &&
      (protocol < 2 || protocol > CURRENT_ENTITLEMENT_PROTOCOL))
  ) {
    throw entitlementUnavailable();
  }
  return {
    entitlement_mode: mode,
    required_client_protocol: protocol,
    mode_version: version,
  };
}

async function resolveEntitlementRollout(
  supabaseAdmin: SupabaseClient,
): Promise<EntitlementRolloutSnapshot> {
  try {
    const { data, error } = await supabaseAdmin.rpc(
      "get_entitlement_rollout_service",
    ).abortSignal(AbortSignal.timeout(5_000));
    const row = singleEntitlementRow(data);
    if (error || !row) throw entitlementUnavailable();
    return rolloutForRow(row);
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
 * Returns a stable 426 envelope after the atomic cutover. During schema-first
 * rollout, protocol 0 deliberately accepts legacy builds. A rollout requiring
 * protocol 2 accepts supported protocols 2-3; requiring 3 excludes unsafe
 * protocol-2 clients.
 */
export async function entitlementProtocolResponse(
  req: Request,
  supabaseAdmin: SupabaseClient,
): Promise<Response | null> {
  const rollout = await resolveEntitlementRollout(supabaseAdmin);
  const presentedProtocol = entitlementProtocolFromRequest(req);
  if (
    rollout.required_client_protocol === 0 ||
    (presentedProtocol != null &&
      presentedProtocol >= rollout.required_client_protocol &&
      presentedProtocol <= CURRENT_ENTITLEMENT_PROTOCOL)
  ) {
    return null;
  }

  return jsonResponse(
    {
      error: "Please update Naturebook to continue identifying.",
      code: "client_update_required",
    },
    426,
    {
      "X-Merian-Required-Entitlement-Protocol": String(
        rollout.required_client_protocol,
      ),
    },
  );
}
