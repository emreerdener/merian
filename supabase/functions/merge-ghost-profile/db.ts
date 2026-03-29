import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { jsonResponse } from "../_shared/edgeHandler.ts";

export async function verifyGhostUser(
  ghostId: string,
  requestingUserId: string,
  supabaseAdmin: SupabaseClient
) {
  const { data: ghostUser, error: ghostUserError } = await supabaseAdmin.auth.admin.getUserById(ghostId);

  if (ghostUserError || !ghostUser?.user) {
    return jsonResponse({ error: "Ghost user not found or already merged." }, 404);
  }

  if (!ghostUser.user.is_anonymous) {
    console.warn(`IDOR attempt: User ${requestingUserId} tried to merge authenticated account ${ghostId}`);
    return jsonResponse({ error: "Forbidden: The target account is not a guest account." }, 403);
  }

  return null; // Passes verification
}

export async function transferScans(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient
) {
  const { error: scansUpdateError } = await supabaseAdmin
    .from("scans")
    .update({ user_id: targetUserId })
    .eq("user_id", ghostId);

  if (scansUpdateError) {
    console.error(`Scans transfer failed from ${ghostId} to ${targetUserId}`);
    throw new Error(`Migration failed: ${scansUpdateError.message}`);
  }
}

export async function purgeGhostUser(
  ghostId: string,
  supabaseAdmin: SupabaseClient
) {
  const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(ghostId);

  if (deleteError) {
    console.warn(`Failed to delete ghost user ${ghostId}: ${deleteError.message}`);
  }
}
