import { serveEdge } from "../_shared/edgeHandler.ts";
import { corsHeaders, parseJsonBody } from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
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

  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;

  try {
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
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
