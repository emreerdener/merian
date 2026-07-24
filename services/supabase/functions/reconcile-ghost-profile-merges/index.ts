import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  parseJsonBody,
  timingSafeCompare,
} from "../_shared/http.ts";
import { reconcileGhostProfileMerges } from "./worker.ts";

function jsonResponse(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function parseLimit(value: unknown): number {
  if (!value || typeof value !== "object" || Array.isArray(value)) return 25;
  const limit = (value as Record<string, unknown>).limit;
  return typeof limit === "number" && Number.isFinite(limit) && limit > 0
    ? Math.trunc(limit)
    : 25;
}

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const providedAuth = req.headers.get("Authorization") ?? "";
  if (
    !serviceRoleKey ||
    !timingSafeCompare(providedAuth, `Bearer ${serviceRoleKey}`)
  ) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      },
    );
    const result = await reconcileGhostProfileMerges(
      supabaseAdmin,
      parseLimit(body),
    );
    return jsonResponse({ success: true, ...result }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(JSON.stringify({
      event: "ghost_profile_merge_reconciliation_failed",
      error: message,
      ts: new Date().toISOString(),
    }));
    return jsonResponse({ error: "Reconciliation failed." }, 500);
  }
});
