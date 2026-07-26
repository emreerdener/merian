import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  parseJsonBody,
  publicErrorResponse,
  timingSafeCompare,
} from "../_shared/http.ts";
import { reconcileExploreMediaHealth } from "./worker.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.min(Math.max(Math.trunc(value), minimum), maximum);
}

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const expectedAuth = `Bearer ${serviceRoleKey}`;
  const providedAuth = req.headers.get("Authorization") ?? "";
  if (
    !serviceRoleKey ||
    !timingSafeCompare(providedAuth, expectedAuth)
  ) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;
  const payload = body && typeof body === "object" && !Array.isArray(body)
    ? body as Record<string, unknown>
    : {};

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey,
    );
    const result = await reconcileExploreMediaHealth(supabaseAdmin, {
      limit: boundedInteger(payload.limit, 1, 500),
      leaseSeconds: boundedInteger(
        payload.leaseSeconds ?? payload.lease_seconds,
        30,
        600,
      ),
    });
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    console.error(JSON.stringify({
      event: "explore_media_health_reconciliation_failed",
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
