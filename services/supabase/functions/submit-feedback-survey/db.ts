import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { FeedbackSurveyInsert } from "./validation.ts";

export async function insertFeedbackSurveyResponse(
  userId: string,
  payload: FeedbackSurveyInsert,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("feedback_survey_responses")
    .insert({
      ...payload,
      user_id: userId,
    });

  if (error) {
    throw new Error(
      `Failed to insert feedback survey response: ${error.message}`,
    );
  }
}
