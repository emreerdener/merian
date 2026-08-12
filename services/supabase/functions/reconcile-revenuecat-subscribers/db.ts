import { SupabaseClient } from "@supabase/supabase-js";

export interface RevenueCatReconciliationClaim {
  userId: string;
  lookupAppUserId: string;
  claimToken: string;
  claimExpiresAt: string;
  allowNonSubscriptionPassGrant: boolean;
}

export interface PurchasePrincipalReconciliationClaim {
  purchasePrincipalId: string;
  lookupAppUserId: string;
  claimToken: string;
  claimExpiresAt: string;
  allowNonSubscriptionPassGrant: boolean;
}

export interface PurchasePrincipalHealth {
  generatedAt: string;
  activePrincipalCount: number;
  pendingPrincipalCount: number;
  unboundActivePrincipalCount: number;
  dueReconciliationCount: number;
  expiredClaimCount: number;
  oldestDueAt: string | null;
  oldestDueAgeSeconds: number | null;
  oldestPendingAt: string | null;
  oldestPendingAgeSeconds: number | null;
}

export interface RevenueCatReconciliationHealth {
  generatedAt: string;
  dueCount: number;
  expiredClaimCount: number;
  oldestDueAt: string | null;
  oldestDueAgeSeconds: number | null;
  signoutPreparedCount: number;
  signoutBoundCount: number;
  oldestSignoutPendingAt: string | null;
  oldestSignoutPendingAgeSeconds: number | null;
}

interface ClaimRow {
  user_id?: unknown;
  lookup_app_user_id?: unknown;
  claim_token?: unknown;
  claim_expires_at?: unknown;
  allow_non_subscription_pass_grant?: unknown;
}

interface HealthRow {
  generated_at?: unknown;
  due_count?: unknown;
  expired_claim_count?: unknown;
  oldest_due_at?: unknown;
  oldest_due_age_seconds?: unknown;
  signout_prepared_count?: unknown;
  signout_bound_count?: unknown;
  oldest_signout_pending_at?: unknown;
  oldest_signout_pending_age_seconds?: unknown;
}

interface PurchasePrincipalClaimRow {
  purchase_principal_id?: unknown;
  lookup_app_user_id?: unknown;
  claim_token?: unknown;
  claim_expires_at?: unknown;
  allow_non_subscription_pass_grant?: unknown;
}

interface PurchasePrincipalHealthRow {
  generated_at?: unknown;
  active_principal_count?: unknown;
  pending_principal_count?: unknown;
  unbound_active_principal_count?: unknown;
  due_reconciliation_count?: unknown;
  expired_claim_count?: unknown;
  oldest_due_at?: unknown;
  oldest_due_age_seconds?: unknown;
  oldest_pending_at?: unknown;
  oldest_pending_age_seconds?: unknown;
}

export class RevenueCatReconciliationDatabaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RevenueCatReconciliationDatabaseError";
  }
}

function requiredString(
  value: unknown,
  field: string,
  subject = "claim",
): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation ${subject} has invalid ${field}.`,
    );
  }
  return value;
}

function nonnegativeSafeInteger(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation health has invalid ${field}.`,
    );
  }
  return value;
}

export async function claimRevenueCatReconciliations(
  supabaseAdmin: SupabaseClient,
  limit = 6,
): Promise<RevenueCatReconciliationClaim[]> {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 25) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation claim has invalid limit.",
    );
  }
  const { data, error } = await supabaseAdmin.rpc(
    "claim_revenuecat_reconciliations",
    { p_limit: limit },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation claim failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data)) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation claim returned an invalid response.",
    );
  }
  if (data.length > limit) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation claim exceeded its requested limit.",
    );
  }

  return data.map(parseClaimRow);
}

export async function claimPurchasePrincipalReconciliations(
  supabaseAdmin: SupabaseClient,
  limit = 6,
): Promise<PurchasePrincipalReconciliationClaim[]> {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 25) {
    throw new RevenueCatReconciliationDatabaseError(
      "Purchase principal reconciliation claim has invalid limit.",
    );
  }
  const { data, error } = await supabaseAdmin.rpc(
    "claim_purchase_principal_reconciliations",
    { p_limit: limit },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `Purchase principal reconciliation claim failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data) || data.length > limit) {
    throw new RevenueCatReconciliationDatabaseError(
      "Purchase principal reconciliation claim returned an invalid response.",
    );
  }
  return data.map((value) => {
    const row = value as PurchasePrincipalClaimRow;
    if (typeof row.allow_non_subscription_pass_grant !== "boolean") {
      throw new RevenueCatReconciliationDatabaseError(
        "Purchase principal reconciliation claim has invalid pass grant policy.",
      );
    }
    return {
      purchasePrincipalId: requiredString(
        row.purchase_principal_id,
        "purchase_principal_id",
      ),
      lookupAppUserId: requiredString(
        row.lookup_app_user_id,
        "lookup_app_user_id",
      ),
      claimToken: requiredString(row.claim_token, "claim_token"),
      claimExpiresAt: requiredString(
        row.claim_expires_at,
        "claim_expires_at",
      ),
      allowNonSubscriptionPassGrant: row.allow_non_subscription_pass_grant,
    };
  });
}

/** Leases only the requested due customer for a foreground identity handoff. */
export async function claimRevenueCatReconciliationForUser(
  supabaseAdmin: SupabaseClient,
  userId: string,
): Promise<RevenueCatReconciliationClaim> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_revenuecat_reconciliation_for_user",
    { p_user_id: userId },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat exact reconciliation claim failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data) || data.length !== 1) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat exact reconciliation claim was unavailable.",
    );
  }
  const claim = parseClaimRow(data[0]);
  if (claim.userId.toLowerCase() !== userId.toLowerCase()) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat exact reconciliation claim returned the wrong user.",
    );
  }
  return claim;
}

function parseClaimRow(value: unknown): RevenueCatReconciliationClaim {
  const row = value as ClaimRow;
  if (typeof row.allow_non_subscription_pass_grant !== "boolean") {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation claim has invalid pass grant fence.",
    );
  }
  return {
    userId: requiredString(row.user_id, "user_id"),
    lookupAppUserId: requiredString(
      row.lookup_app_user_id,
      "lookup_app_user_id",
    ),
    claimToken: requiredString(row.claim_token, "claim_token"),
    claimExpiresAt: requiredString(row.claim_expires_at, "claim_expires_at"),
    allowNonSubscriptionPassGrant: row.allow_non_subscription_pass_grant,
  };
}

export async function getRevenueCatReconciliationHealth(
  supabaseAdmin: SupabaseClient,
): Promise<RevenueCatReconciliationHealth> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_revenuecat_reconciliation_health",
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation health read failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data) || data.length !== 1) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation health returned an invalid response.",
    );
  }

  const row = data[0] as HealthRow;
  const generatedAt = requiredString(
    row.generated_at,
    "generated_at",
    "health",
  );
  if (!Number.isFinite(Date.parse(generatedAt))) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation health has invalid generated_at.",
    );
  }
  const dueCount = nonnegativeSafeInteger(row.due_count, "due_count");
  const expiredClaimCount = nonnegativeSafeInteger(
    row.expired_claim_count,
    "expired_claim_count",
  );
  const oldestDueAt = row.oldest_due_at === null
    ? null
    : requiredString(row.oldest_due_at, "oldest_due_at", "health");
  const oldestDueAgeSeconds = row.oldest_due_age_seconds === null
    ? null
    : nonnegativeSafeInteger(
      row.oldest_due_age_seconds,
      "oldest_due_age_seconds",
    );
  const hasSignoutHealth = [
    row.signout_prepared_count,
    row.signout_bound_count,
    row.oldest_signout_pending_at,
    row.oldest_signout_pending_age_seconds,
  ].some((value) => value !== undefined);
  const signoutPreparedCount = hasSignoutHealth
    ? nonnegativeSafeInteger(
      row.signout_prepared_count,
      "signout_prepared_count",
    )
    : 0;
  const signoutBoundCount = hasSignoutHealth
    ? nonnegativeSafeInteger(row.signout_bound_count, "signout_bound_count")
    : 0;
  const oldestSignoutPendingAt = !hasSignoutHealth ||
      row.oldest_signout_pending_at === null
    ? null
    : requiredString(
      row.oldest_signout_pending_at,
      "oldest_signout_pending_at",
      "health",
    );
  const oldestSignoutPendingAgeSeconds = !hasSignoutHealth ||
      row.oldest_signout_pending_age_seconds === null
    ? null
    : nonnegativeSafeInteger(
      row.oldest_signout_pending_age_seconds,
      "oldest_signout_pending_age_seconds",
    );
  const signoutPendingCount = signoutPreparedCount + signoutBoundCount;

  if (
    (oldestDueAt === null) !== (oldestDueAgeSeconds === null) ||
    (oldestDueAt !== null && !Number.isFinite(Date.parse(oldestDueAt))) ||
    (dueCount === 0 && oldestDueAt !== null) ||
    (dueCount > 0 && oldestDueAt === null) ||
    (oldestSignoutPendingAt !== null &&
      !Number.isFinite(Date.parse(oldestSignoutPendingAt))) ||
    (oldestSignoutPendingAt === null) !==
      (oldestSignoutPendingAgeSeconds === null) ||
    (signoutPendingCount === 0 && oldestSignoutPendingAt !== null) ||
    (signoutPendingCount > 0 && oldestSignoutPendingAt === null)
  ) {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation health returned inconsistent backlog state.",
    );
  }

  return {
    generatedAt,
    dueCount,
    expiredClaimCount,
    oldestDueAt,
    oldestDueAgeSeconds,
    signoutPreparedCount,
    signoutBoundCount,
    oldestSignoutPendingAt,
    oldestSignoutPendingAgeSeconds,
  };
}

export async function getPurchasePrincipalHealth(
  supabaseAdmin: SupabaseClient,
): Promise<PurchasePrincipalHealth> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_purchase_principal_health",
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `Purchase principal health read failed: ${error.message}`,
    );
  }
  if (!Array.isArray(data) || data.length !== 1) {
    throw new RevenueCatReconciliationDatabaseError(
      "Purchase principal health returned an invalid response.",
    );
  }
  const row = data[0] as PurchasePrincipalHealthRow;
  const generatedAt = requiredString(
    row.generated_at,
    "generated_at",
    "principal health",
  );
  const oldestDueAt = optionalTimestamp(
    row.oldest_due_at,
    "oldest_due_at",
  );
  const oldestPendingAt = optionalTimestamp(
    row.oldest_pending_at,
    "oldest_pending_at",
  );
  const oldestDueAgeSeconds = optionalNonnegativeInteger(
    row.oldest_due_age_seconds,
    "oldest_due_age_seconds",
  );
  const oldestPendingAgeSeconds = optionalNonnegativeInteger(
    row.oldest_pending_age_seconds,
    "oldest_pending_age_seconds",
  );
  if (
    !Number.isFinite(Date.parse(generatedAt)) ||
    (oldestDueAt === null) !== (oldestDueAgeSeconds === null) ||
    (oldestPendingAt === null) !== (oldestPendingAgeSeconds === null)
  ) {
    throw new RevenueCatReconciliationDatabaseError(
      "Purchase principal health returned inconsistent state.",
    );
  }
  return {
    generatedAt,
    activePrincipalCount: nonnegativeSafeInteger(
      row.active_principal_count,
      "active_principal_count",
    ),
    pendingPrincipalCount: nonnegativeSafeInteger(
      row.pending_principal_count,
      "pending_principal_count",
    ),
    unboundActivePrincipalCount: nonnegativeSafeInteger(
      row.unbound_active_principal_count,
      "unbound_active_principal_count",
    ),
    dueReconciliationCount: nonnegativeSafeInteger(
      row.due_reconciliation_count,
      "due_reconciliation_count",
    ),
    expiredClaimCount: nonnegativeSafeInteger(
      row.expired_claim_count,
      "expired_claim_count",
    ),
    oldestDueAt,
    oldestDueAgeSeconds,
    oldestPendingAt,
    oldestPendingAgeSeconds,
  };
}

export async function applyRevenueCatReconciliation(
  claim: RevenueCatReconciliationClaim,
  authoritativeSnapshotAtMs: number,
  targetTier: "free" | "pro",
  targetExpiresAt: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "apply_revenuecat_reconciliation",
    {
      p_user_id: claim.userId,
      p_claim_token: claim.claimToken,
      p_authoritative_snapshot_at_ms: authoritativeSnapshotAtMs,
      p_target_tier: targetTier,
      p_target_expires_at: targetExpiresAt,
    },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation apply failed: ${error.message}`,
    );
  }
  if (typeof data !== "boolean") {
    throw new RevenueCatReconciliationDatabaseError(
      "RevenueCat reconciliation apply returned an invalid response.",
    );
  }
  return data;
}

export async function failRevenueCatReconciliation(
  claim: RevenueCatReconciliationClaim,
  errorCode: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "fail_revenuecat_reconciliation",
    {
      p_user_id: claim.userId,
      p_claim_token: claim.claimToken,
      p_error_code: errorCode,
    },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation failure write failed: ${error.message}`,
    );
  }
}

export async function applyPurchasePrincipalReconciliation(
  claim: PurchasePrincipalReconciliationClaim,
  authoritativeSnapshotAtMs: number,
  storeTier: "free" | "pro",
  storeExpiresAt: string | null,
  accountGrantTier: "free" | "pro",
  accountGrantExpiresAt: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "apply_purchase_principal_reconciliation",
    {
      p_purchase_principal_id: claim.purchasePrincipalId,
      p_claim_token: claim.claimToken,
      p_authoritative_snapshot_at_ms: authoritativeSnapshotAtMs,
      p_store_tier: storeTier,
      p_store_expires_at: storeExpiresAt,
      p_account_grant_tier: accountGrantTier,
      p_account_grant_expires_at: accountGrantExpiresAt,
    },
  );
  if (error || typeof data !== "boolean") {
    throw new RevenueCatReconciliationDatabaseError(
      error
        ? `Purchase principal reconciliation apply failed: ${error.message}`
        : "Purchase principal reconciliation apply returned an invalid response.",
    );
  }
  return data;
}

export async function failPurchasePrincipalReconciliation(
  claim: PurchasePrincipalReconciliationClaim,
  errorCode: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "fail_purchase_principal_reconciliation",
    {
      p_purchase_principal_id: claim.purchasePrincipalId,
      p_claim_token: claim.claimToken,
      p_error_code: errorCode,
    },
  );
  if (error) {
    throw new RevenueCatReconciliationDatabaseError(
      `Purchase principal reconciliation failure write failed: ${error.message}`,
    );
  }
}

function optionalTimestamp(value: unknown, field: string): string | null {
  if (value === null) return null;
  const parsed = requiredString(value, field, "principal health");
  if (!Number.isFinite(Date.parse(parsed))) {
    throw new RevenueCatReconciliationDatabaseError(
      `Purchase principal health has invalid ${field}.`,
    );
  }
  return parsed;
}

function optionalNonnegativeInteger(
  value: unknown,
  field: string,
): number | null {
  return value === null ? null : nonnegativeSafeInteger(value, field);
}
