import { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";

interface ExploreCommentLookup {
  id: string;
  post_id: string;
  user_id: string;
  deleted_at: string | null;
  moderated_at: string | null;
  post?: { user_id?: string | null; unshared_at?: string | null } | {
    user_id?: string | null;
    unshared_at?: string | null;
  }[] | null;
}

function relationValue<T>(value: T | T[] | null | undefined): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function makeHttpError(status: number, message: string): PublicHttpError {
  return publicHttpError(status, message);
}

export async function fetchReportableComment(
  commentId: string,
  reporterUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ commentId: string; postId: string; commentAuthorUserId: string }> {
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

  if (row.user_id === reporterUserId) {
    throw makeHttpError(400, "You cannot report your own comment.");
  }

  if (
    post?.unshared_at != null || row.deleted_at != null ||
    row.moderated_at != null
  ) {
    throw makeHttpError(404, "Explore comment is no longer available.");
  }

  return {
    commentId: row.id,
    postId: row.post_id,
    commentAuthorUserId: row.user_id,
  };
}

export async function upsertExploreCommentReport(
  input: {
    commentId: string;
    postId: string;
    reporterUserId: string;
    commentAuthorUserId: string;
    reason: string;
    details: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_comment_reports")
    .upsert({
      comment_id: input.commentId,
      post_id: input.postId,
      reporter_user_id: input.reporterUserId,
      comment_author_user_id: input.commentAuthorUserId,
      reason: input.reason,
      details: input.details,
    }, {
      onConflict: "comment_id,reporter_user_id",
      ignoreDuplicates: false,
    });

  if (error) {
    throw new Error(`Failed to save Explore comment report: ${error.message}`);
  }
}
