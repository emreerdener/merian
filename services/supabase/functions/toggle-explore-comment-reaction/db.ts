import { SupabaseClient } from "@supabase/supabase-js";

export async function toggleExploreCommentReaction(
  commentId: string,
  userId: string,
  emoji: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error: selectError } = await supabaseAdmin
    .from("explore_comment_reactions")
    .select("id")
    .eq("comment_id", commentId)
    .eq("user_id", userId)
    .eq("emoji", emoji)
    .maybeSingle();

  if (selectError) {
    throw new Error(`Failed to check existing reaction: ${selectError.message}`);
  }

  if (data) {
    const { error: deleteError } = await supabaseAdmin
      .from("explore_comment_reactions")
      .delete()
      .eq("id", data.id);

    if (deleteError) {
      throw new Error(`Failed to remove reaction: ${deleteError.message}`);
    }
  } else {
    const { error: insertError } = await supabaseAdmin
      .from("explore_comment_reactions")
      .insert({
        comment_id: commentId,
        user_id: userId,
        emoji: emoji,
      });

    if (insertError) {
      // Ignore unique violation if another request beat us to it
      if (insertError.code !== "23505") {
        throw new Error(`Failed to add reaction: ${insertError.message}`);
      }
    }
  }
}
