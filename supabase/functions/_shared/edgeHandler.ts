import { createClient, SupabaseClient, User } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { requireAuth } from "./auth.ts";
import { corsHeaders } from "./cors.ts";

/**
 * Standardized JSON response helper dropping boilerplate instantiation overhead.
 */
export function jsonResponse(payload: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status
  });
}

/**
 * Universal Deno Edge Function wrapper consolidating OPTIONS preflights, 
 * Zero-Trust Supabase Authentication boundaries, and global error swallowing.
 */
export async function withEdgeHandler(
  req: Request,
  handler: (user: User, supabaseAdmin: SupabaseClient) => Promise<Response>
): Promise<Response> {
  // 1. CORS Preflight Execution
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 2. Service Role Client Instantiation
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // 3. Native JWT Authentication Interceptor 
    const { user, response } = await requireAuth(req, supabaseAdmin);
    
    if (response || !user) {
      return response || jsonResponse({ error: "Unauthorized: Missing authentication context." }, 401);
    }

    // 4. Authorized Handler Execution Callback
    return await handler(user, supabaseAdmin);
  } catch (error: unknown) {
    console.error("Critical Edge exception natively suppressed:", error);
    
    const msg = error instanceof Error ? error.message : "Internal Server Fault";
    
    // Abstract Postgres or API layer HTTP generic exception bounds securely
    const customStatus = error && typeof error === "object" && "status" in error
      ? (error as Record<string, unknown>).status as number
      : 500;
      
    return jsonResponse({ error: msg }, customStatus);
  }
}
