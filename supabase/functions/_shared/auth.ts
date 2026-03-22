import { SupabaseClient, User } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { corsHeaders } from "./cors.ts";

export async function requireAuth(
  req: Request,
  supabaseAdmin: SupabaseClient
): Promise<{ user: User | null; response: Response | null }> {
  // 1. JWT Authentication Trap
  const authHeader = req.headers.get("Authorization")?.replace("Bearer ", "");
  
  if (!authHeader) {
    return {
      user: null,
      response: new Response(JSON.stringify({ error: "Unauthorized: Missing HTTP Bearer Context" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    };
  }

  // 2. JWT Verification against PostgreSQL
  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(authHeader);

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
