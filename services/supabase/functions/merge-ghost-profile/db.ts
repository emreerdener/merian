import { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import {
  buildPreservedGhostIdentityUpdate,
  type GhostPublicIdentitySnapshot,
} from "./identity.ts";

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

/// Re-parents Ask the Community requests before the ghost public user is
/// deleted. `explore_community_requests.requested_by` cascades on
/// public.users deletion, so leaving it pointed at the ghost account would
/// silently delete active community requests during account merge.
export async function transferCommunityRequests(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("explore_community_requests")
    .update({ requested_by: targetUserId })
    .eq("requested_by", ghostId);

  if (error) {
    throw new Error(`Community requests migration failed: ${error.message}`);
  }
}

/// Re-parents follow relationships created while the user was anonymous.
/// The SQL RPC dedupes conflicts before the ghost public user is deleted.
export async function transferUserFollows(
  ghostId: string,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin.rpc("reparent_user_follows", {
    ghost_id: ghostId,
    target_user_id: targetUserId,
  });

  if (error) {
    throw new Error(`Follow relationship migration failed: ${error.message}`);
  }
}

export async function fetchGhostPublicIdentity(
  ghostId: string,
  supabaseAdmin: SupabaseClient,
): Promise<GhostPublicIdentitySnapshot | null> {
  const { data: ghostIdentity, error: identityError } = await supabaseAdmin
    .from("users")
    .select(
      "public_username,public_author_name,public_identity_source,custom_avatar_url,custom_avatar_updated_at",
    )
    .eq("id", ghostId)
    .maybeSingle();

  if (identityError) {
    throw new Error(
      `Failed to snapshot ghost public identity: ${identityError.message}`,
    );
  }
  if (!ghostIdentity) return null;

  const { data: defaultUsername, error: defaultUsernameError } =
    await supabaseAdmin.rpc("build_default_public_username", {
      target_user_id: ghostId,
    });

  if (defaultUsernameError) {
    throw new Error(
      `Failed to resolve ghost default username: ${defaultUsernameError.message}`,
    );
  }

  return {
    publicUsername: ghostIdentity.public_username as string | null,
    publicAuthorName: ghostIdentity.public_author_name as string | null,
    publicIdentitySource: ghostIdentity.public_identity_source as string | null,
    customAvatarUrl: ghostIdentity.custom_avatar_url as string | null,
    customAvatarUpdatedAt: ghostIdentity.custom_avatar_updated_at as
      | string
      | null,
    defaultPublicUsername: typeof defaultUsername === "string"
      ? defaultUsername
      : null,
  };
}

export async function applyPreservedGhostIdentity(
  snapshot: GhostPublicIdentitySnapshot | null,
  targetUserId: string,
  supabaseAdmin: SupabaseClient,
) {
  const update = buildPreservedGhostIdentityUpdate(snapshot);
  if (Object.keys(update).length === 0) return;

  const { error } = await supabaseAdmin
    .from("users")
    .update(update)
    .eq("id", targetUserId);

  if (error) {
    throw new Error(`Ghost identity preservation failed: ${error.message}`);
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
