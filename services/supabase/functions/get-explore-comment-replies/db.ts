import { SupabaseClient } from "@supabase/supabase-js";

export interface ExploreCommentReplyRow {
  comment_id: string;
  post_id: string;
  parent_comment_id: string | null;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  body: string;
  created_at: string;
  viewer_can_delete: boolean;
  viewer_can_moderate: boolean;
  viewer_can_report: boolean;
  reply_count: number;
  reactions: any[] | null;
}

interface ExploreRepliesCursor {
  afterCreatedAt: string | null;
  afterCommentId: string | null;
}

export async function fetchExploreCommentReplies(
  userId: string,
  parentCommentId: string,
  limit: number,
  cursor: ExploreRepliesCursor,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreCommentReplyRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_comment_replies", {
    self_id: userId,
    target_parent_comment_id: parentCommentId,
    max_limit: limit,
    after_created_at: cursor.afterCreatedAt,
    after_comment_id: cursor.afterCommentId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore comment replies: ${error.message}`);
  }

  return (data ?? []) as ExploreCommentReplyRow[];
}
