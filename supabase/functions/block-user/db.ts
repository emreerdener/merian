import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function insertUserBlock(
  blockerId: string,
  blockedId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("user_blocks")
    .insert({
      blocker_id: blockerId,
      blocked_id: blockedId,
    });

  if (error) {
    throw new Error(`Failed to block user: ${error.message}`);
  }
}
