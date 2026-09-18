import { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";

export async function toggleExploreCommentReaction(
  commentId: string,
  userId: string,
  emoji: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc("toggle_explore_comment_reaction", {
    self_id: userId,
    target_id: commentId,
    requested_emoji: emoji,
  });
  if (error?.code === "42501") {
    throw publicHttpError(403, "This reaction is no longer available.");
  }
  if (error?.code === "22023") {
    throw publicHttpError(400, "Choose one supported emoji.");
  }
  if (error) throw new Error("Failed to update comment reaction.");
}
