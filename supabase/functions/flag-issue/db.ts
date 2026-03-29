import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function insertFlagRecord(
  scanId: string,
  userId: string,
  flagReason: string,
  userSuggestion: string | undefined,
  supabaseAdmin: SupabaseClient,
) {
  const { error: insertError } = await supabaseAdmin
    .from("flagged_reviews")
    .insert({
      scan_id: scanId,
      user_id: userId,
      flag_reason: flagReason,
      user_suggestion: userSuggestion,
    });

  if (insertError) {
    throw new Error(
      `Failed to insert flagged review record: ${insertError.message}`,
    );
  }
}

export async function markScanAsFlagged(
  scanId: string,
  flagReason: string,
  userSuggestion: string | undefined,
  supabaseAdmin: SupabaseClient,
) {
  const notes = `Flag Reason: ${flagReason} | Suggestion: ${
    userSuggestion ?? "None"
  }`;

  const { error: updateError } = await supabaseAdmin
    .from("scans")
    .update({
      is_flagged: true,
      human_intervention_notes: notes,
    })
    .eq("id", scanId);

  if (updateError) {
    throw new Error(`Failed to update scan record: ${updateError.message}`);
  }
}
