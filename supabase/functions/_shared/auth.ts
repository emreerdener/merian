import {
  createClient,
  SupabaseClient,
  User,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "./http.ts";

export function bearerTokenFromAuthorizationHeader(
  authorizationHeader: string | null,
): string | null {
  const match = authorizationHeader?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

export function authFailureCode(message: string | undefined): string {
  const normalizedMessage = message?.toLowerCase() ?? "";
  if (normalizedMessage.includes("auth session missing")) {
    return "auth_session_missing";
  }

  return "invalid_session_token";
}

export async function requireAuth(
  req: Request,
  _supabaseAdmin: SupabaseClient,
): Promise<{ user: User | null; response: Response | null }> {
  const rawAuthHeader = req.headers.get("Authorization");
  const bearerToken = bearerTokenFromAuthorizationHeader(rawAuthHeader);

  if (!bearerToken) {
    console.error("requireAuth: Missing Authorization header in request.");
    return {
      user: null,
      response: new Response(
        JSON.stringify({
          error: "Unauthorized: Missing Authorization header.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      ),
    };
  }

  // Create a client scoped to the request's Bearer token to validate the JWT.
  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: `Bearer ${bearerToken}` } } },
  );

  // Edge Functions are stateless; pass the JWT explicitly instead of relying
  // on a persisted SDK session.
  const { data: { user }, error: authError } = await supabaseClient.auth
    .getUser(bearerToken);

  if (authError || !user) {
    const message = authError?.message || "Invalid or expired session token.";
    console.error("requireAuth: Supabase getUser() failed.", authError);
    return {
      user: null,
      response: new Response(
        JSON.stringify({
          code: authFailureCode(message),
          error: `Unauthorized: ${message}`,
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      ),
    };
  }

  return { user, response: null };
}
