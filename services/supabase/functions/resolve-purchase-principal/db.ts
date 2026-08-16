import type { SupabaseClient } from "@supabase/supabase-js";
import type { RevenueCatEntitlementState } from "../revenuecat-webhook/subscriber.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PurchasePrincipalResolutionStart =
  | {
    mode: "legacy";
    minimumClientProtocol: number;
  }
  | {
    mode: "stable";
    purchasePrincipalId: string;
    revenueCatAppUserId: string;
    minimumClientProtocol: number;
    bindingIntentGeneration: number;
    allowNonSubscriptionPassGrant: boolean | null;
  };

export interface PurchasePrincipalBinding {
  purchasePrincipalId: string;
  revenueCatAppUserId: string;
  bindingGeneration: number;
  accountGrantsAllowed: boolean;
  alreadyBound: boolean;
}

export interface PurchasePrincipalSignoutRotationPreparation {
  rotationId: string;
  purchasePrincipalId: string;
  revenueCatAppUserId: string;
  bindingGeneration: number;
  status: "prepared";
  expiresAt: string;
  alreadyPrepared: boolean;
}

export interface PurchasePrincipalSignoutRotationClaim {
  purchasePrincipalId: string;
  revenueCatAppUserId: string;
  bindingGeneration: number;
  accountGrantsAllowed: boolean;
  rotationId: string;
  status: "completed";
  expiresAt: string;
  alreadyClaimed: boolean;
}

export interface PurchasePrincipalSignoutRotationCancellation {
  rotationId: string;
  status: "cancelled" | "expired";
  expiresAt: string;
  alreadyCancelled: boolean;
}

type StartRow = {
  resolution_mode?: unknown;
  purchase_principal_id?: unknown;
  revenuecat_app_user_id?: unknown;
  minimum_client_protocol?: unknown;
  requires_attestation?: unknown;
  binding_intent_generation?: unknown;
  allow_non_subscription_pass_grant?: unknown;
};

type CompleteRow = {
  purchase_principal_id?: unknown;
  revenuecat_app_user_id?: unknown;
  binding_generation?: unknown;
  account_grants_allowed?: unknown;
  already_bound?: unknown;
};

type RotationRow = {
  rotation_id?: unknown;
  purchase_principal_id?: unknown;
  revenuecat_app_user_id?: unknown;
  binding_generation?: unknown;
  account_grants_allowed?: unknown;
  rotation_status?: unknown;
  expires_at?: unknown;
  already_prepared?: unknown;
  already_claimed?: unknown;
  already_cancelled?: unknown;
};

export class PurchasePrincipalDatabaseError extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    message: string,
  ) {
    super(message);
    this.name = "PurchasePrincipalDatabaseError";
  }
}

export async function beginPurchasePrincipalResolution(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
  capabilityHash: string,
  clientProtocol: number,
  bindingIntentGeneration: number,
): Promise<PurchasePrincipalResolutionStart> {
  const { data, error } = await supabaseAdmin.rpc(
    "begin_purchase_principal_resolution",
    {
      p_auth_user_id: authUserId,
      p_capability_hash: capabilityHash,
      p_client_protocol: clientProtocol,
      p_binding_intent_generation: bindingIntentGeneration,
    },
  );
  const row = singleRow(data, error, "purchase principal begin") as StartRow;
  const mode = row.resolution_mode;
  const minimumClientProtocol = requiredPositiveInteger(
    row.minimum_client_protocol,
    "minimum_client_protocol",
  );
  if (mode === "legacy") {
    if (
      row.purchase_principal_id !== null ||
      row.revenuecat_app_user_id !== null ||
      row.requires_attestation !== false ||
      row.binding_intent_generation !== null ||
      row.allow_non_subscription_pass_grant !== null
    ) {
      throw invalidResponse("legacy resolution fields");
    }
    return { mode, minimumClientProtocol };
  }
  if (mode !== "stable" || row.requires_attestation !== true) {
    throw invalidResponse("resolution_mode");
  }
  const resolvedBindingIntentGeneration = requiredPositiveInteger(
    row.binding_intent_generation,
    "binding_intent_generation",
  );
  if (resolvedBindingIntentGeneration !== bindingIntentGeneration) {
    throw invalidResponse("binding_intent_generation");
  }
  return {
    mode,
    purchasePrincipalId: requiredUuid(
      row.purchase_principal_id,
      "purchase_principal_id",
    ),
    revenueCatAppUserId: requiredAppUserId(
      row.revenuecat_app_user_id,
      "revenuecat_app_user_id",
    ),
    minimumClientProtocol,
    bindingIntentGeneration: resolvedBindingIntentGeneration,
    allowNonSubscriptionPassGrant: optionalBoolean(
      row.allow_non_subscription_pass_grant,
      "allow_non_subscription_pass_grant",
    ),
  };
}

/**
 * Reads the current server projection used to authorize adoption of detached
 * non-renewing pass history. Completion repeats this check while holding the
 * user lock, so this read is only a fail-closed derivation input, not authority.
 */
export async function readCurrentEntitlementProjection(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
): Promise<RevenueCatEntitlementState> {
  let response;
  try {
    response = await supabaseAdmin
      .from("users")
      .select("subscription_tier,subscription_expires_at")
      .eq("id", authUserId)
      .limit(1);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "network failure";
    throw new PurchasePrincipalDatabaseError(
      "purchase_principal_entitlement_projection_unavailable",
      true,
      `Purchase principal entitlement projection read failed: ${detail}`,
    );
  }
  const { data, error } = response;
  if (
    error || !Array.isArray(data) || data.length !== 1 || !isRecord(data[0])
  ) {
    throw new PurchasePrincipalDatabaseError(
      "purchase_principal_entitlement_projection_unavailable",
      true,
      `Purchase principal entitlement projection was unavailable: ${
        error?.message ?? "invalid response"
      }`,
    );
  }
  const tier = data[0].subscription_tier;
  const expiresAt = data[0].subscription_expires_at;
  if (
    (tier !== "free" && tier !== "pro") ||
    (expiresAt !== null &&
      (typeof expiresAt !== "string" ||
        !Number.isFinite(Date.parse(expiresAt)))) ||
    (tier === "free" && expiresAt !== null)
  ) {
    throw invalidResponse("entitlement projection");
  }
  return { targetTier: tier, expiresAt };
}

export async function completePurchasePrincipalResolution(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
  start: Extract<PurchasePrincipalResolutionStart, { mode: "stable" }>,
  capabilityHash: string,
  authoritativeSnapshotAtMs: number,
  storeState: RevenueCatEntitlementState,
  allowNonSubscriptionPassGrant: boolean,
  accountGrantState: RevenueCatEntitlementState,
): Promise<PurchasePrincipalBinding> {
  const { data, error } = await supabaseAdmin.rpc(
    "complete_purchase_principal_resolution",
    {
      p_auth_user_id: authUserId,
      p_purchase_principal_id: start.purchasePrincipalId,
      p_capability_hash: capabilityHash,
      p_binding_intent_generation: start.bindingIntentGeneration,
      p_authoritative_snapshot_at_ms: authoritativeSnapshotAtMs,
      p_store_tier: storeState.targetTier,
      p_store_expires_at: storeState.expiresAt,
      p_allow_non_subscription_pass_grant: allowNonSubscriptionPassGrant,
      p_account_grant_tier: accountGrantState.targetTier,
      p_account_grant_expires_at: accountGrantState.expiresAt,
    },
  );
  const row = singleRow(
    data,
    error,
    "purchase principal completion",
  ) as CompleteRow;
  const result: PurchasePrincipalBinding = {
    purchasePrincipalId: requiredUuid(
      row.purchase_principal_id,
      "purchase_principal_id",
    ),
    revenueCatAppUserId: requiredAppUserId(
      row.revenuecat_app_user_id,
      "revenuecat_app_user_id",
    ),
    bindingGeneration: requiredPositiveInteger(
      row.binding_generation,
      "binding_generation",
    ),
    accountGrantsAllowed: requiredBoolean(
      row.account_grants_allowed,
      "account_grants_allowed",
    ),
    alreadyBound: requiredBoolean(row.already_bound, "already_bound"),
  };
  if (
    result.purchasePrincipalId !== start.purchasePrincipalId ||
    result.revenueCatAppUserId !== start.revenueCatAppUserId
  ) {
    throw invalidResponse("stable identity continuity");
  }
  return result;
}

export async function preparePurchasePrincipalSignoutRotation(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
  capabilityHash: string,
  rotationId: string,
  secretHash: string,
  expectedBindingGeneration: number,
  clientProtocol: number,
): Promise<PurchasePrincipalSignoutRotationPreparation> {
  const { data, error } = await supabaseAdmin.rpc(
    "prepare_purchase_principal_signout_rotation",
    {
      p_auth_user_id: authUserId,
      p_capability_hash: capabilityHash,
      p_rotation_id: rotationId,
      p_secret_hash: secretHash,
      p_expected_binding_generation: expectedBindingGeneration,
      p_client_protocol: clientProtocol,
    },
  );
  const row = singleRow(
    data,
    error,
    "purchase principal sign-out rotation preparation",
  ) as RotationRow;
  const result: PurchasePrincipalSignoutRotationPreparation = {
    rotationId: requiredUuid(row.rotation_id, "rotation_id"),
    purchasePrincipalId: requiredUuid(
      row.purchase_principal_id,
      "purchase_principal_id",
    ),
    revenueCatAppUserId: requiredAppUserId(
      row.revenuecat_app_user_id,
      "revenuecat_app_user_id",
    ),
    bindingGeneration: requiredPositiveInteger(
      row.binding_generation,
      "binding_generation",
    ),
    status: requiredRotationStatus(row.rotation_status, ["prepared"]),
    expiresAt: requiredTimestamp(row.expires_at, "expires_at"),
    alreadyPrepared: requiredBoolean(
      row.already_prepared,
      "already_prepared",
    ),
  };
  if (result.rotationId !== rotationId.toLowerCase()) {
    throw invalidResponse("sign-out rotation identity continuity");
  }
  return result;
}

export async function claimPurchasePrincipalSignoutRotation(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
  capabilityHash: string,
  rotationId: string,
  secretHash: string,
  clientProtocol: number,
): Promise<PurchasePrincipalSignoutRotationClaim> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_purchase_principal_signout_rotation",
    {
      p_auth_user_id: authUserId,
      p_capability_hash: capabilityHash,
      p_rotation_id: rotationId,
      p_secret_hash: secretHash,
      p_client_protocol: clientProtocol,
    },
  );
  const row = singleRow(
    data,
    error,
    "purchase principal sign-out rotation claim",
  ) as RotationRow;
  const status = requiredRotationStatus(row.rotation_status, [
    "completed",
    "expired",
  ]);
  if (status === "expired") {
    throw new PurchasePrincipalDatabaseError(
      "purchase_principal_signout_rotation_expired",
      false,
      "Purchase principal sign-out rotation expired.",
    );
  }
  const result: PurchasePrincipalSignoutRotationClaim = {
    rotationId: requiredUuid(row.rotation_id, "rotation_id"),
    purchasePrincipalId: requiredUuid(
      row.purchase_principal_id,
      "purchase_principal_id",
    ),
    revenueCatAppUserId: requiredAppUserId(
      row.revenuecat_app_user_id,
      "revenuecat_app_user_id",
    ),
    bindingGeneration: requiredPositiveInteger(
      row.binding_generation,
      "binding_generation",
    ),
    accountGrantsAllowed: requiredBoolean(
      row.account_grants_allowed,
      "account_grants_allowed",
    ),
    status,
    expiresAt: requiredTimestamp(row.expires_at, "expires_at"),
    alreadyClaimed: requiredBoolean(row.already_claimed, "already_claimed"),
  };
  if (
    result.rotationId !== rotationId.toLowerCase() ||
    result.accountGrantsAllowed
  ) {
    throw invalidResponse("sign-out rotation claim continuity");
  }
  return result;
}

export async function cancelPurchasePrincipalSignoutRotation(
  supabaseAdmin: SupabaseClient,
  authUserId: string,
  capabilityHash: string,
  rotationId: string,
  secretHash: string,
  clientProtocol: number,
): Promise<PurchasePrincipalSignoutRotationCancellation> {
  const { data, error } = await supabaseAdmin.rpc(
    "cancel_purchase_principal_signout_rotation",
    {
      p_auth_user_id: authUserId,
      p_capability_hash: capabilityHash,
      p_rotation_id: rotationId,
      p_secret_hash: secretHash,
      p_client_protocol: clientProtocol,
    },
  );
  const row = singleRow(
    data,
    error,
    "purchase principal sign-out rotation cancellation",
  ) as RotationRow;
  const result: PurchasePrincipalSignoutRotationCancellation = {
    rotationId: requiredUuid(row.rotation_id, "rotation_id"),
    status: requiredRotationStatus(row.rotation_status, [
      "cancelled",
      "expired",
    ]),
    expiresAt: requiredTimestamp(row.expires_at, "expires_at"),
    alreadyCancelled: requiredBoolean(
      row.already_cancelled,
      "already_cancelled",
    ),
  };
  if (result.rotationId !== rotationId.toLowerCase()) {
    throw invalidResponse("sign-out rotation cancellation continuity");
  }
  return result;
}

function singleRow(
  data: unknown,
  error: { message: string; code?: string } | null,
  operation: string,
): Record<string, unknown> {
  if (error) {
    const code = databasePublicCode(error.message);
    throw new PurchasePrincipalDatabaseError(
      code,
      databaseErrorIsRetryable(error.code, code),
      `${operation} failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data) || data.length !== 1 || !isRecord(data[0])) {
    throw invalidResponse(operation);
  }
  return data[0];
}

function databasePublicCode(message: string): string {
  const known = [
    "purchase_principal_capability_revoked",
    "purchase_principal_user_not_available",
    "purchase_principal_invalid_resolution",
    "purchase_principal_invalid_entitlement_state",
    "purchase_principal_rollout_changed",
    "purchase_principal_client_upgrade_required",
    "purchase_principal_binding_intent_stale",
    "purchase_principal_entitlement_projection_changed",
    "purchase_principal_account_deletion_in_progress",
    "purchase_principal_signout_rotation_required",
    "purchase_principal_signout_rotation_invalid",
    "purchase_principal_signout_rotation_unavailable",
    "purchase_principal_signout_rotation_already_prepared",
    "purchase_principal_signout_rotation_terminal_conflict",
    "purchase_principal_signout_rotation_expired",
    "purchase_principal_signout_source_not_available",
    "purchase_principal_signout_anonymous_destination_required",
    "purchase_principal_signout_fresh_anonymous_destination_required",
    "purchase_principal_signout_account_deletion_in_progress",
    "purchase_principal_signout_ghost_merge_in_progress",
    "purchase_principal_signout_binding_changed",
    "purchase_principal_signout_binding_audit_missing",
  ];
  return known.find((candidate) => message.includes(candidate)) ??
    "purchase_principal_unavailable";
}

function databaseErrorIsRetryable(
  code: string | undefined,
  publicCode: string,
): boolean {
  if (
    [
      "purchase_principal_signout_rotation_required",
      "purchase_principal_signout_rotation_invalid",
      "purchase_principal_signout_rotation_unavailable",
      "purchase_principal_signout_rotation_already_prepared",
      "purchase_principal_signout_rotation_terminal_conflict",
      "purchase_principal_signout_rotation_expired",
      "purchase_principal_signout_anonymous_destination_required",
      "purchase_principal_signout_fresh_anonymous_destination_required",
      "purchase_principal_signout_binding_changed",
    ].includes(publicCode)
  ) {
    return false;
  }
  if (publicCode === "purchase_principal_signout_binding_audit_missing") {
    return true;
  }
  return code === undefined || code.startsWith("08") ||
    [
      "40001",
      "40P01",
      "53300",
      "55P03",
      "57014",
      "57P01",
      "P0002",
    ].includes(code);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requiredUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw invalidResponse(field);
  }
  return value.toLowerCase();
}

function containsAsciiControlCharacter(value: string): boolean {
  for (const character of value) {
    const scalar = character.codePointAt(0);
    if (scalar !== undefined && (scalar <= 0x1f || scalar === 0x7f)) {
      return true;
    }
  }
  return false;
}

function requiredAppUserId(value: unknown, field: string): string {
  if (
    typeof value !== "string" || value.length < 1 || value.length > 255 ||
    containsAsciiControlCharacter(value) ||
    value.startsWith("$RCAnonymousID:")
  ) {
    throw invalidResponse(field);
  }
  return value;
}

function requiredPositiveInteger(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw invalidResponse(field);
  }
  return value as number;
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw invalidResponse(field);
  return value;
}

function requiredTimestamp(value: unknown, field: string): string {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    throw invalidResponse(field);
  }
  return value;
}

function requiredRotationStatus<T extends string>(
  value: unknown,
  accepted: readonly T[],
): T {
  if (typeof value !== "string" || !accepted.includes(value as T)) {
    throw invalidResponse("rotation_status");
  }
  return value as T;
}

function optionalBoolean(value: unknown, field: string): boolean | null {
  if (value === null) return null;
  return requiredBoolean(value, field);
}

function invalidResponse(field: string): PurchasePrincipalDatabaseError {
  return new PurchasePrincipalDatabaseError(
    "purchase_principal_invalid_response",
    true,
    `Purchase principal database returned invalid ${field}.`,
  );
}
