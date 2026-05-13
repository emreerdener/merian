import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreCommentRow {
  comment_id: string;
  post_id: string;
  author_user_id: string;
  author_name: string;
  author_avatar_url?: string | null;
  body: string;
  created_at: string;
  viewer_can_delete: boolean;
  viewer_can_moderate: boolean;
  viewer_can_report: boolean;
  reactions: any[] | null;
}

interface ExploreCommentsCursor {
  afterCreatedAt: string | null;
  afterCommentId: string | null;
}

export async function fetchExploreComments(
  userId: string,
  postId: string,
  limit: number,
  cursor: ExploreCommentsCursor,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreCommentRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_comments", {
    self_id: userId,
    target_post_id: postId,
    max_limit: limit,
    after_created_at: cursor.afterCreatedAt,
    after_comment_id: cursor.afterCommentId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore comments: ${error.message}`);
  }

  return (data ?? []) as ExploreCommentRow[];
}
