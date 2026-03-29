import {
  createClient,
  SupabaseClient,
  User,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireAuth } from "./auth.ts";
import { corsHeaders, jsonResponse } from "./http.ts";

export { jsonResponse };

/**
 * Schedules a background task using EdgeRuntime.waitUntil when available,
 * falling back gracefully for local development.
 */
export function runBackground(task: Promise<void>): void {
  const globalObj = globalThis as unknown as { EdgeRuntime?: { waitUntil: (p: Promise<void>) => void } };
  if (typeof globalObj.EdgeRuntime === "object" && typeof globalObj.EdgeRuntime.waitUntil === "function") {
    globalObj.EdgeRuntime.waitUntil(task);
  } else {
    task.catch(console.error);
  }
}

/**
 * Universal Deno edge function wrapper handling CORS preflights,
 * JWT authentication, and top-level error handling.
 */
export async function withEdgeHandler(
  req: Request,
  handler: (user: User, supabaseAdmin: SupabaseClient) => Promise<Response>
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { user, response } = await requireAuth(req, supabaseAdmin);

    if (response || !user) {
      return response || jsonResponse({ error: "Unauthorized" }, 401);
    }

    return await handler(user, supabaseAdmin);
  } catch (error: unknown) {
    console.error("Edge function error:", error);
    const msg = error instanceof Error ? error.message : "Internal Server Error";
    const customStatus = error && typeof error === "object" && "status" in error
      ? (error as Record<string, unknown>).status as number
      : 500;
    return jsonResponse({ error: msg }, customStatus);
  }
}
