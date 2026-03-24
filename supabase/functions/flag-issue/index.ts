import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { scanId, flagReason, userSuggestion } = await req.json();

    if (!scanId || !flagReason) {
      return jsonResponse({ error: "Missing required parameters: 'scanId' and 'flagReason' must be provided." }, 400);
    }

    // 1. Insert a moderation queue record
    const { error: insertError } = await supabaseAdmin
      .from("flagged_reviews")
      .insert({
        scan_id: scanId,
        user_id: user.id,
        flag_reason: flagReason,
        user_suggestion: userSuggestion
      });

    if (insertError) {
      throw new Error(`Failed to insert flagged review record: ${insertError.message}`);
    }

    // 2. Mark the scan as flagged
    const { error: updateError } = await supabaseAdmin
      .from("scans")
      .update({
        is_flagged: true,
        human_intervention_notes: `Flag Reason: ${flagReason} | Suggestion: ${userSuggestion ?? "None"}`
      })
      .eq("id", scanId);

    if (updateError) {
      throw new Error(`Failed to update scan record: ${updateError.message}`);
    }

    return jsonResponse({ success: true, message: "Report submitted for moderation." }, 200);
  })
);
