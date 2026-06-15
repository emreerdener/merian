import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface InsertedExploreComment {
  id: string;
  post_id: string;
  parent_comment_id?: string | null;
  created_at: string;
}

export interface ExploreCommentMentionRow {
  user_id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
}

export interface ExploreReplyParent {
  id: string;
  post_id: string;
  user_id: string;
  parent_comment_id?: string | null;
  deleted_at?: string | null;
  moderated_at?: string | null;
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchReplyParent(
  parentCommentId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreReplyParent> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_comments")
    .select("id,post_id,user_id,parent_comment_id,deleted_at,moderated_at")
    .eq("id", parentCommentId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore parent comment not found.");
  }

  const parent = data as ExploreReplyParent;
  if (parent.post_id !== postId) {
    throw makeHttpError(
      400,
      "parent_comment_id must belong to the same Explore post.",
    );
  }
  if (parent.parent_comment_id != null) {
    throw makeHttpError(400, "Replies can only target top-level comments.");
  }
  if (parent.deleted_at != null || parent.moderated_at != null) {
    throw makeHttpError(404, "Explore parent comment is no longer available.");
  }

  return parent;
}

export async function insertExploreComment(
  postId: string,
  userId: string,
  body: string,
  parentCommentId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<InsertedExploreComment> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_comments")
    .insert({
      post_id: postId,
      user_id: userId,
      body,
      parent_comment_id: parentCommentId,
    })
    .select("id,post_id,parent_comment_id,created_at")
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to create Explore comment: ${error?.message ?? "Unknown error"}`,
    );
  }

  return data as InsertedExploreComment;
}

export async function insertExploreCommentMentionsFromBody(
  commentId: string,
  actorUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreCommentMentionRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "insert_explore_comment_mentions_from_body",
    {
      target_comment_id: commentId,
      actor_user_id: actorUserId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to resolve Explore comment mentions: ${error.message}`,
    );
  }

  return (data ?? []) as ExploreCommentMentionRow[];
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
    throw new Error(
      `Failed to fetch Explore comment count: ${error?.message ?? "No data"}`,
    );
  }

  return Number(data.comment_count ?? 0);
}
