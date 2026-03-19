import { serve } from "@std/http/server.ts";
import { createClient } from "@supabase/supabase-js";

import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) throw new Error("Missing Authorization header");

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
      return new Response(JSON.stringify({ error: "Invalid or expired Session" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { scanId, userId, flagReason, userSuggestion } = await req.json();

    if (!scanId || !userId || !flagReason) {
      return new Response(JSON.stringify({ error: "Missing required parameters." }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
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

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
