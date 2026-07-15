import { SupabaseClient } from "@supabase/supabase-js";
import { CommunityFeedbackInsert } from "./validation.ts";

export async function insertCommunityFeedback(
  userId: string,
  payload: CommunityFeedbackInsert,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("community_feedback")
    .insert({
      ...payload,
      user_id: userId,
    });

  if (error) {
    throw new Error(
      `Failed to insert community feedback: ${error.message}`,
    );
  }
}
