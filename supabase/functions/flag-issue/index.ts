import { serve } from "@std/http/server.ts";
import { withEdgeHandler, jsonResponse } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { scanId, flagReason, userSuggestion } = await req.json();
    const userId = user.id;

    if (!scanId || !flagReason) {
      return jsonResponse({ error: "Missing required parameters." }, 400);
    }

    // Insert into flagged_reviews
    const { error: insertError } = await supabaseAdmin
      .from('flagged_reviews')
      .insert({
        scan_id: scanId,
        user_id: userId,
        flag_reason: flagReason,
        user_suggestion: userSuggestion
      });

    if (insertError) throw new Error(`Insert failed: ${insertError.message}`);

    // Update scans
    const { error: updateError } = await supabaseAdmin
      .from('scans')
      .update({ 
        is_flagged: true, 
        human_intervention_notes: `Flag Reason: ${flagReason} | Suggestion: ${userSuggestion ?? 'None'}` 
      })
      .eq('id', scanId);

    if (updateError) throw new Error(`Update failed: ${updateError.message}`);

    return jsonResponse({ success: true }, 200);
}));
