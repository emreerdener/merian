import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface InsertedExploreComment {
  id: string;
  post_id: string;
  created_at: string;
}

export async function insertExploreComment(
  postId: string,
  userId: string,
  body: string,
  supabaseAdmin: SupabaseClient,
): Promise<InsertedExploreComment> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_comments")
    .insert({
      post_id: postId,
      user_id: userId,
      body,
    })
    .select("id,post_id,created_at")
    .single();

  if (error || !data) {
    throw new Error(`Failed to create Explore comment: ${error?.message ?? "Unknown error"}`);
  }

  return data as InsertedExploreComment;
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
