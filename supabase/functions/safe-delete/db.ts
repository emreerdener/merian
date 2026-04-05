import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { logStructuredError } from "../_shared/edgeHandler.ts";

export async function queueStorageDeletion(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error: deletionError } = await supabaseAdmin
    .from("pending_storage_deletions")
    .insert({ target_user_id: userId, status: "pending" });

  if (deletionError) {
    // Do not throw — failing to queue the cleanup record must not block account deletion,
    // which has already revoked JWT and tombstoned the user. Log as a structured alert so
    // the orphaned R2 files surface in monitoring for manual cleanup.
    logStructuredError("safe_delete/queue_storage_deletion_failed", {
      userId,
      error: deletionError.message,
    });
  }
}

export async function applyUserTombstone(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error: rpcError } = await supabaseAdmin.rpc("apply_user_tombstone", {
    target_user_id: userId,
  });

  if (rpcError) {
    throw new Error(`Failed to apply user tombstone: ${rpcError.message}`);
  }
}

export async function deleteAuthProfile(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error: deleteUserError } = await supabaseAdmin.auth.admin.deleteUser(
    userId,
  );

  if (deleteUserError) {
    throw new Error(
      `Failed to delete auth profile: ${deleteUserError.message}`,
    );
  }
}
