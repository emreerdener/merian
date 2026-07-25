import type { SupabaseClient } from "@supabase/supabase-js";

export type StorageDeletionClaim = {
  deletionId: string;
  targetUserId: string;
  objectPrefix: string;
  startAfterKey: string | null;
  phase: "sweep" | "verification";
  claimToken: string;
  claimExpiresAt: string;
};

type StorageDeletionClaimRow = {
  deletion_id: unknown;
  target_user_id: unknown;
  object_prefix: unknown;
  start_after_key: unknown;
  deletion_phase: unknown;
  claim_token: unknown;
  claim_expires_at: unknown;
};

export async function claimStorageDeletionJobs(
  supabaseAdmin: SupabaseClient,
  limit: number,
): Promise<StorageDeletionClaim[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_pending_storage_deletions",
    { p_limit: limit },
  );
  if (error) throw new Error("Could not claim storage deletion jobs.");

  return ((data ?? []) as StorageDeletionClaimRow[]).map((row) => {
    if (
      typeof row.deletion_id !== "string" ||
      typeof row.target_user_id !== "string" ||
      typeof row.object_prefix !== "string" ||
      (row.start_after_key !== null &&
        typeof row.start_after_key !== "string") ||
      (row.deletion_phase !== "sweep" &&
        row.deletion_phase !== "verification") ||
      typeof row.claim_token !== "string" ||
      typeof row.claim_expires_at !== "string"
    ) {
      throw new Error("Storage deletion claim returned invalid state.");
    }

    return {
      deletionId: row.deletion_id,
      targetUserId: row.target_user_id,
      objectPrefix: row.object_prefix,
      startAfterKey: row.start_after_key,
      phase: row.deletion_phase,
      claimToken: row.claim_token,
      claimExpiresAt: row.claim_expires_at,
    };
  });
}

export async function advanceStorageDeletionJob(
  supabaseAdmin: SupabaseClient,
  claim: StorageDeletionClaim,
  lastKey: string | null,
  prefixFinished: boolean,
): Promise<"pending" | "verifying" | "completed"> {
  const { data, error } = await supabaseAdmin.rpc(
    "advance_pending_storage_deletion",
    {
      p_deletion_id: claim.deletionId,
      p_claim_token: claim.claimToken,
      p_last_key: lastKey,
      p_prefix_finished: prefixFinished,
    },
  );
  if (
    error ||
    (data !== "pending" && data !== "verifying" && data !== "completed")
  ) {
    throw new Error("Could not advance storage deletion progress.");
  }
  return data;
}

export async function failStorageDeletionJob(
  supabaseAdmin: SupabaseClient,
  claim: StorageDeletionClaim,
  errorCode: string,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "fail_pending_storage_deletion",
    {
      p_deletion_id: claim.deletionId,
      p_claim_token: claim.claimToken,
      p_error_code: errorCode,
    },
  );
  if (error || data !== true) {
    throw new Error("Could not release failed storage deletion claim.");
  }
}
