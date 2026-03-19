import { corsHeaders } from "./cors.ts";
import { requireAuth } from "./auth.ts";
import { createClient, User, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

/**
 * Standardized JSON response helper dropping boilerplate instantiation overhead.
 */
export function jsonResponse(payload: any, status: number = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

/**
 * Universal Deno Edge Function wrapper consolidating OPTIONS preflights, 
 * Zero-Trust Supabase Authentication boundaries, and error swallowing globally.
 */
export async function withEdgeHandler(
  req: Request,
  handler: (user: User, supabaseAdmin: SupabaseClient) => Promise<Response>
): Promise<Response> {
  // 1. CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 2. Auth Boundary
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );
    const { user, response } = await requireAuth(req, supabaseAdmin);
    if (response || !user) {
        return response || new Response("Unauthorized", { status: 401 });
    }

    // 3. Execution
    return await handler(user, supabaseAdmin);
  } catch (error: unknown) {
    console.error("Critical Edge exception natively suppressed:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    // @ts-ignore - status exists on Supabase exceptions natively
    const status = error && typeof error === 'object' && 'status' in error ? error.status as number : 500;
    return jsonResponse({ error: msg }, status);
  }
}
