import { SupabaseClient } from "@supabase/supabase-js";

export async function setExplorePostLike(
  postId: string,
  userId: string,
  liked: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (liked) {
    const { error } = await supabaseAdmin
      .from("explore_post_likes")
      .upsert(
        { post_id: postId, user_id: userId },
        { onConflict: "post_id,user_id", ignoreDuplicates: true },
      );

    if (error) {
      throw new Error(`Failed to like Explore post: ${error.message}`);
    }
    return;
  }

  const { error } = await supabaseAdmin
    .from("explore_post_likes")
    .delete()
    .eq("post_id", postId)
    .eq("user_id", userId);

  if (error) {
    throw new Error(`Failed to unlike Explore post: ${error.message}`);
  }
}

export async function fetchExplorePostLikeCount(
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select("like_count")
    .eq("id", postId)
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to fetch Explore like count: ${error?.message ?? "No data"}`,
    );
  }

  return Number(data.like_count ?? 0);
}
