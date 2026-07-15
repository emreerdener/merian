import { createClient as createClaimsClient } from "@supabase/supabase-js-claims";
import type {
  SupabaseClient,
  User,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  authFailureCode,
  bearerTokenFromAuthorizationHeader,
  validateVerifiedClaims,
} from "./auth.ts";
import { corsHeaders } from "./http.ts";

function unauthorizedClaimsResponse(message: string): Response {
  return new Response(
    JSON.stringify({
      code: authFailureCode(message),
      error: `Unauthorized: ${message}`,
    }),
    {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

/**
 * Verifies asymmetric JWTs against Supabase's cached JWKS path. Supabase's SDK
 * safely falls back to the Auth server for legacy symmetric signing projects.
 *
 * This module is imported only by latency-sensitive routes. Keeping it out of
 * edgeHandler.ts prevents every authenticated function from bundling the
 * newer claims-capable SDK alongside the repository's compatibility SDK.
 */
export async function requireClaimsAuth(
  req: Request,
  _supabaseAdmin: SupabaseClient,
): Promise<{ user: User | null; response: Response | null }> {
  const bearerToken = bearerTokenFromAuthorizationHeader(
    req.headers.get("Authorization"),
  );
  if (!bearerToken) {
    return {
      user: null,
      response: unauthorizedClaimsResponse("Missing Authorization header."),
    };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseClient = createClaimsClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: `Bearer ${bearerToken}` } } },
  );
  const { data, error } = await supabaseClient.auth.getClaims(bearerToken);
  if (error || !data?.claims) {
    const message = error?.message || "Invalid or expired session token.";
    console.error("requireClaimsAuth: Supabase getClaims() failed.", error);
    return { user: null, response: unauthorizedClaimsResponse(message) };
  }

  const validation = validateVerifiedClaims(
    data.claims,
    `${supabaseUrl.replace(/\/$/, "")}/auth/v1`,
  );
  if (!validation.valid) {
    return {
      user: null,
      response: unauthorizedClaimsResponse(validation.message),
    };
  }

  const claims = validation.claims;
  const user = {
    id: claims.sub,
    aud: "authenticated",
    role: "authenticated",
    email: typeof claims.email === "string" ? claims.email : undefined,
    phone: typeof claims.phone === "string" ? claims.phone : undefined,
    app_metadata: claims.app_metadata ?? {},
    user_metadata: claims.user_metadata ?? {},
    identities: [],
    factors: [],
    created_at: typeof claims.iat === "number"
      ? new Date(claims.iat * 1000).toISOString()
      : new Date(0).toISOString(),
    is_anonymous: claims.is_anonymous === true,
  } as unknown as User;

  return { user, response: null };
}
