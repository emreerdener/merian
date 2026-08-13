import { createClient as createClaimsClient } from "@supabase/supabase-js";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import {
  authFailureCode,
  bearerTokenFromAuthorizationHeader,
  validateVerifiedClaims,
} from "./auth.ts";
import { corsHeaders } from "./http.ts";
import { createDeadlineFetchTransport } from "./outbound.ts";
import { requirePublicApiKeyFromEnvironment } from "./publishableKey.ts";

const SUPABASE_CLAIMS_REQUEST_TIMEOUT_MS = 15_000;

function unauthorizedClaimsResponse(
  diagnosticMessage: string,
  publicMessage = "Invalid or expired session token.",
): Response {
  return new Response(
    JSON.stringify({
      code: authFailureCode(diagnosticMessage),
      error: `Unauthorized: ${publicMessage}`,
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
 * This module is imported only by latency-sensitive routes. The fleet shares
 * one exact Supabase SDK version, but keeping this policy out of edgeHandler.ts
 * prevents every authenticated function from silently switching from the
 * established getUser behavior to cached-JWKS claims authentication.
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
      response: unauthorizedClaimsResponse(
        "Missing Authorization header.",
        "Missing Authorization header.",
      ),
    };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseClient = createClaimsClient(
    supabaseUrl,
    requirePublicApiKeyFromEnvironment(),
    {
      global: {
        fetch: createDeadlineFetchTransport(
          SUPABASE_CLAIMS_REQUEST_TIMEOUT_MS,
        ),
        headers: { Authorization: `Bearer ${bearerToken}` },
      },
    },
  );
  const { data, error } = await supabaseClient.auth.getClaims(bearerToken);
  if (error || !data?.claims) {
    const message = error?.message || "Invalid or expired session token.";
    console.error("auth_claims_validation_failed");
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
