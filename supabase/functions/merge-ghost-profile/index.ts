import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing Authorization header");
    }

    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    });

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
      return new Response(JSON.stringify({ error: "Invalid or expired Session" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const targetUserId = user.id;

    const body = await req.json();
    const ghost_id = body.ghost_id;

    if (!ghost_id) {
       return new Response(JSON.stringify({ error: "Missing ghost_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (ghost_id === targetUserId) {
       return new Response(JSON.stringify({ message: "No merge required" }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // CRITICAL: Validate the requested ghost_id is actually an Anonymous Ghost User natively before obliterating it.
    // This forcibly prevents IDOR Account Takeover (ATO) strikes stealing and deleting fully authenticated Apple/Google profiles.
    const { data: ghostUser, error: ghostUserError } = await supabaseAdmin.auth.admin.getUserById(ghost_id);
    
    if (ghostUserError || !ghostUser?.user) {
       return new Response(JSON.stringify({ error: "Ghost user account not found or already merged." }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!ghostUser.user.is_anonymous) {
       console.error(`IDOR ATO Attempt: User ${targetUserId} attempted to blindly steal fully authenticated account ${ghost_id}`);
       return new Response(JSON.stringify({ error: "Forbidden: The requested profile is fully authenticated and cannot be hijacked." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Securely transfer PostgreSQL scans ownership from the Ghost UUID to the newly verified session.user.id
    const { error: scansUpdateError } = await supabaseAdmin
      .from("scans")
      .update({ user_id: targetUserId })
      .eq("user_id", ghost_id);

    if (scansUpdateError) {
      console.error(`Scans ownership update failed for ${ghost_id} to ${targetUserId}`);
      throw scansUpdateError;
    }

    // Eradicate Ghost user identity permanently to prevent abandoned orphaned accounts
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(ghost_id);

    if (deleteError) {
      console.error(`Erasing Ghost ID ${ghost_id} completely failed natively: ${deleteError.message}`);
    }

    return new Response(JSON.stringify({ success: true, targetUserId }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("Merge Ghost Profile failed:", message);
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
