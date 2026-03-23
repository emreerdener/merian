import { SupabaseClient, User, createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { corsHeaders } from "./cors.ts";

export async function requireAuth(
  req: Request,
  _supabaseAdmin: SupabaseClient
): Promise<{ user: User | null; response: Response | null }> {
  // 1. JWT Authentication Trap
  const rawAuthHeader = req.headers.get("Authorization");
  
  if (!rawAuthHeader) {
    return {
      user: null,
      response: new Response(JSON.stringify({ error: "Unauthorized: Missing HTTP Bearer Context" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    };
  }

  // 2. JWT Verification against PostgreSQL Context
  // Creates a dynamically scoped client explicitly passing the Bearer token as its authentication scope to extract the user natively
  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: rawAuthHeader } } }
  );

  const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

  // 3. Reject Spoofed Signatures
  if (authError || !user) {
    return {
      user: null,
      response: new Response(
        JSON.stringify({ error: `Unauthorized: ${authError?.message || "Invalid or expired session token."}` }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    };
  }

  return { user, response: null };
}
