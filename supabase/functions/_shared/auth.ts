import { SupabaseClient, User, createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { corsHeaders } from "./cors.ts";

export async function requireAuth(
  req: Request,
  _supabaseAdmin: SupabaseClient
): Promise<{ user: User | null; response: Response | null }> {
  const rawAuthHeader = req.headers.get("Authorization");

  if (!rawAuthHeader) {
    return {
      user: null,
      response: new Response(JSON.stringify({ error: "Unauthorized: Missing Authorization header." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    };
  }

  // Create a client scoped to the request's Bearer token to validate the JWT.
  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: rawAuthHeader } } }
  );

  const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

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
