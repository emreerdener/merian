import type { SupabaseClient } from "@supabase/supabase-js";

export type GhostMergeCleanupClaim = {
  handoffId: string;
  ghostUserId: string;
  targetUserId: string;
  claimToken: string;
};

type GhostMergeCleanupClaimRow = {
  handoff_id: string;
  ghost_user_id: string;
  target_user_id: string;
  claim_token: string;
};

export async function claimGhostMergeAuthCleanups(
  supabaseAdmin: SupabaseClient,
  limit: number,
): Promise<GhostMergeCleanupClaim[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_ghost_profile_merge_auth_cleanups",
    { p_limit: limit },
  );

  if (error) {
    throw new Error(`Could not claim ghost Auth cleanups: ${error.message}`);
  }

  return ((data ?? []) as GhostMergeCleanupClaimRow[]).map((row) => ({
    handoffId: row.handoff_id,
    ghostUserId: row.ghost_user_id,
    targetUserId: row.target_user_id,
    claimToken: row.claim_token,
  }));
}

export async function finishGhostMergeAuthCleanup(
  supabaseAdmin: SupabaseClient,
  claim: GhostMergeCleanupClaim,
  succeeded: boolean,
  errorCode: string | null,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "finish_ghost_profile_merge_auth_cleanup",
    {
      p_handoff_id: claim.handoffId,
      p_claim_token: claim.claimToken,
      p_succeeded: succeeded,
      p_error_code: errorCode,
    },
  );

  if (error) {
    throw new Error(
      `Could not finish ghost Auth cleanup ${claim.handoffId}: ${error.message}`,
    );
  }
}
