import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    });

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

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
