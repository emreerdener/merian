import { serveEdge } from "../_shared/edgeHandler.ts";

import {
  corsHeaders,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import {
  reconcileScanMediaAssets,
  type ReconcileScanMediaAssetsOptions,
} from "./worker.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function positiveNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : undefined;
}

function parseOptions(value: unknown): ReconcileScanMediaAssetsOptions {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const body = value as Record<string, unknown>;
  const limit = positiveNumber(body.limit);
  const repairAfterMinutes = positiveNumber(body.repairAfterMinutes) ??
    positiveNumber(body.repair_after_minutes);
  const abandonAfterHours = positiveNumber(body.abandonAfterHours) ??
    positiveNumber(body.abandon_after_hours);

  return {
    limit: limit ? Math.trunc(limit) : undefined,
    repairAfterMinutes,
    abandonAfterHours,
    dryRun: body.dryRun === true || body.dry_run === true,
  };
}

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAdmin = createServiceRoleClient(
      supabaseUrl,
      auth.serverApiKey,
    );
    const result = await reconcileScanMediaAssets(
      supabaseAdmin,
      parseOptions(body),
    );

    return jsonResponse({ success: true, ...result }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(JSON.stringify({
      event: "scan_media_reconciliation_failed",
      error: message,
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
