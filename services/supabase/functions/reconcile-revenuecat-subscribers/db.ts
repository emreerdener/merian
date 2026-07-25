import { SupabaseClient } from "@supabase/supabase-js";

export interface RevenueCatReconciliationClaim {
  userId: string;
  lookupAppUserId: string;
  claimToken: string;
  claimExpiresAt: string;
  allowNonSubscriptionPassGrant: boolean;
}

interface ClaimRow {
  user_id?: unknown;
  lookup_app_user_id?: unknown;
  claim_token?: unknown;
  claim_expires_at?: unknown;
  allow_non_subscription_pass_grant?: unknown;
}

export class RevenueCatReconciliationDatabaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RevenueCatReconciliationDatabaseError";
  }
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new RevenueCatReconciliationDatabaseError(
      `RevenueCat reconciliation claim has invalid ${field}.`,
    );
  }
  return value;
}

export async function claimRevenueCatReconciliations(
  supabaseAdmin: SupabaseClient,
  limit = 10,
): Promise<RevenueCatReconciliationClaim[]> {
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
