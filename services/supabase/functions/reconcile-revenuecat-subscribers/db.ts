import { SupabaseClient } from "@supabase/supabase-js";

export interface RevenueCatReconciliationClaim {
  userId: string;
  lookupAppUserId: string;
  claimToken: string;
  claimExpiresAt: string;
  allowNonSubscriptionPassGrant: boolean;
}

export interface RevenueCatReconciliationHealth {
  generatedAt: string;
  dueCount: number;
  expiredClaimCount: number;
  oldestDueAt: string | null;
  oldestDueAgeSeconds: number | null;
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

  return data.map((value) => {
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
      claimExpiresAt: requiredString(
        row.claim_expires_at,
        "claim_expires_at",
      ),
      allowNonSubscriptionPassGrant: row.allow_non_subscription_pass_grant,
    };
  });
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

  if (
    (oldestDueAt === null) !== (oldestDueAgeSeconds === null) ||
    (oldestDueAt !== null && !Number.isFinite(Date.parse(oldestDueAt))) ||
    (dueCount === 0 && oldestDueAt !== null) ||
    (dueCount > 0 && oldestDueAt === null)
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
