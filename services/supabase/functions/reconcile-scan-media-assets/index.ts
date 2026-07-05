import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { corsHeaders, timingSafeCompare } from "../_shared/http.ts";
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";

  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: unknown = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);
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
    return jsonResponse({ error: message }, 500);
  }
});
