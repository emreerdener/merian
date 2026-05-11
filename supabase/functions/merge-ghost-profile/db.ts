import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { jsonResponse } from "../_shared/edgeHandler.ts";

export async function verifyGhostUser(
  ghostId: string,
  requestingUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { data: ghostUser, error: ghostUserError } = await supabaseAdmin.auth
    .admin.getUserById(ghostId);

  if (ghostUserError || !ghostUser?.user) {
    return jsonResponse(
      { error: "Ghost user not found or already merged." },
      404,
    );
  }

  if (!ghostUser.user.is_anonymous) {
    console.warn(
      `IDOR attempt: User ${requestingUserId} tried to merge authenticated account ${ghostId}`,
    );
    return jsonResponse({
      error: "Forbidden: The target account is not a guest account.",
    }, 403);
  }

  return null; // Passes verification
}

export async function transferScans(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
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

/// Re-parents all collections owned by the ghost user to the target authenticated user.
/// Must be called BEFORE purgeGhostUser — the ON DELETE CASCADE on auth.users would
/// otherwise silently drop these rows when the ghost is deleted.
/// collection_scans rows need no update: they reference collection_id (unchanged) and
/// scan_id (scan IDs are unchanged by transferScans — only their user_id moved).
export async function transferCollections(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("collections")
    .update({ user_id: targetUserId })
    .eq("user_id", ghostId);

  if (error) {
    throw new Error(`Collections migration failed: ${error.message}`);
  }
}

/// Re-parents Explore posts published while the user was still anonymous.
/// Explore posts duplicate the scan owner into `explore_posts.user_id` for feed
/// indexes and author-profile reads, so scan transfer alone is not enough.
export async function transferExplorePosts(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("explore_posts")
    .update({ user_id: targetUserId })
    .eq("user_id", ghostId);

  if (error) {
    throw new Error(`Explore posts migration failed: ${error.message}`);
  }
}

export async function purgeGhostUser(
  ghostId: string,
  supabaseAdmin: SupabaseClient,
) {
  // Delete auth.users first — cascades to collections and export_jobs (both reference auth.users).
  const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(
    ghostId,
  );

  if (deleteError) {
    console.warn(
      `Failed to delete ghost user ${ghostId}: ${deleteError.message}`,
    );
  }

  // public.users has no FK to auth.users, so it must be deleted explicitly.
  // This cascades to flagged_reviews and user_blocks referencing the ghost user,
  // which is the correct outcome — ghost-user reports and blocks have no value
  // after the identity has been merged into the authenticated account.
  const { error: publicUserDeleteError } = await supabaseAdmin
    .from("users")
    .delete()
    .eq("id", ghostId);

  if (publicUserDeleteError) {
    console.warn(
      `Failed to delete public.users for ghost ${ghostId}: ${publicUserDeleteError.message}`,
    );
  }
}
