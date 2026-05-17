import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ExploreCommentLookup {
  id: string;
  post_id: string;
  user_id: string;
  deleted_at: string | null;
  moderated_at: string | null;
  post?: { user_id?: string | null; unshared_at?: string | null } | { user_id?: string | null; unshared_at?: string | null }[] | null;
}

function relationValue<T>(value: T | T[] | null | undefined): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchDeletableComment(
  commentId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ postId: string; action: "deleted" | "moderated" }> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_comments")
    .select(`
      id,
      post_id,
      user_id,
      deleted_at,
      moderated_at,
      post:explore_posts!inner(user_id,unshared_at)
    `)
    .eq("id", commentId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore comment not found.");
  }

  const row = data as ExploreCommentLookup;
  const post = relationValue(row.post);

  if (row.deleted_at != null || row.moderated_at != null) {
    return { postId: row.post_id, action: "deleted" };
  }

  if (row.user_id === userId) {
    return { postId: row.post_id, action: "deleted" };
  }

  if (post?.user_id === userId) {
    return { postId: row.post_id, action: "moderated" };
  }

  if (row.user_id !== userId && post?.user_id !== userId) {
    throw makeHttpError(403, "You cannot delete this Explore comment.");
  }

  return { postId: row.post_id, action: "deleted" };
}

export async function removeExploreComment(
  commentId: string,
  action: "deleted" | "moderated",
  actingUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const removalPayload = action === "moderated"
    ? {
      moderated_at: new Date().toISOString(),
      moderated_by_user_id: actingUserId,
    }
    : {
      deleted_at: new Date().toISOString(),
    };

  const { error } = await supabaseAdmin
    .from("explore_post_comments")
    .update(removalPayload)
    .eq("id", commentId)
    .is("deleted_at", null)
    .is("moderated_at", null);

  if (error) {
    throw new Error(`Failed to delete Explore comment: ${error.message}`);
  }
}

export async function fetchExplorePostCommentCount(
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select("comment_count")
    .eq("id", postId)
    .single();

  if (error || !data) {
    throw new Error(`Failed to fetch Explore comment count: ${error?.message ?? "No data"}`);
  }

  return Number(data.comment_count ?? 0);
}
