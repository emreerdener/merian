import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function insertUserBlock(
  blockerId: string,
  blockedId: string,
  supabaseAdmin: SupabaseClient,
) {
  // ignoreDuplicates: true makes repeated block requests idempotent — tapping
  // "Block" twice or retrying after a network failure will not throw a unique
  // constraint violation (23505) for the (blocker_id, blocked_id) pair.
  const { error } = await supabaseAdmin
    .from("user_blocks")
    .upsert(
      { blocker_id: blockerId, blocked_id: blockedId },
      { onConflict: "blocker_id,blocked_id", ignoreDuplicates: true },
    );

  if (error) {
    throw new Error(`Failed to block user: ${error.message}`);
  }

  const { error: followDeleteError } = await supabaseAdmin
    .from("user_follows")
    .delete()
    .or(
      `and(follower_user_id.eq.${blockerId},followee_user_id.eq.${blockedId}),and(follower_user_id.eq.${blockedId},followee_user_id.eq.${blockerId})`,
    );

  if (followDeleteError) {
    throw new Error(
      `Failed to remove follow relationships for blocked user: ${followDeleteError.message}`,
    );
  }
}
