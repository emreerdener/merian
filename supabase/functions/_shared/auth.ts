import { SupabaseClient, User } from "@supabase/supabase-js";
import { corsHeaders } from "./cors.ts";

export async function requireAuth(req: Request, supabaseAdmin: SupabaseClient): Promise<{ user: User | null; response: Response | null }> {
  const authHeader = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!authHeader) {
    return {
      user: null,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      )
    };
  }

  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(authHeader);

  if (authError || !user) {
    return {
      user: null,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      )
    };
  }

  return { user, response: null };
}