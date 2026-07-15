import {
  createClient,
  SupabaseClient,
  User,
} from "@supabase/supabase-js";
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
