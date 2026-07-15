import {
  createClient,
  SupabaseClient,
  User,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createClient as createClaimsClient } from "https://esm.sh/@supabase/supabase-js@2.110.6";
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

export function validateVerifiedClaims(
  rawClaims: unknown,
  expectedIssuer: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): { valid: true; claims: Record<string, unknown> } | {
  valid: false;
  message: string;
} {
  if (!rawClaims || typeof rawClaims !== "object" || Array.isArray(rawClaims)) {
    return { valid: false, message: "Invalid session claims." };
  }

  const claims = rawClaims as Record<string, unknown>;
  const sub = typeof claims.sub === "string" ? claims.sub : "";
  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidPattern.test(sub)) {
    return { valid: false, message: "Invalid session subject." };
  }

  const issuer = typeof claims.iss === "string"
    ? claims.iss.replace(/\/$/, "")
    : "";
  if (issuer !== expectedIssuer.replace(/\/$/, "")) {
    return { valid: false, message: "Invalid session issuer." };
  }

  const audiences = Array.isArray(claims.aud)
    ? claims.aud.filter((value): value is string => typeof value === "string")
    : (typeof claims.aud === "string" ? [claims.aud] : []);
  if (!audiences.includes("authenticated")) {
    return { valid: false, message: "Invalid session audience." };
  }

  const expiration = typeof claims.exp === "number" ? claims.exp : 0;
  if (!Number.isFinite(expiration) || expiration <= nowSeconds) {
    return { valid: false, message: "Session token has expired." };
  }

  if (claims.nbf != null) {
    const notBefore = typeof claims.nbf === "number" ? claims.nbf : NaN;
    if (!Number.isFinite(notBefore) || notBefore > nowSeconds + 30) {
      return { valid: false, message: "Session token is not active." };
    }
  }

  if (claims.role !== "authenticated") {
    return { valid: false, message: "Invalid session role." };
  }

  return { valid: true, claims };
}

/**
 * Verifies asymmetric JWTs against Supabase's cached JWKS path. Supabase's SDK
 * safely falls back to the Auth server for legacy symmetric signing projects.
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
