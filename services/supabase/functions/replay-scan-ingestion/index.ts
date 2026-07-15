import { createClient } from "@supabase/supabase-js";

import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import { replayScanIngestion } from "./worker.ts";

function positiveNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : undefined;
}

function parseOptions(body: Record<string, unknown>) {
  const limit = positiveNumber(body.limit);
  const leaseSeconds = positiveNumber(body.leaseSeconds) ??
    positiveNumber(body.lease_seconds);
  const retryAfterMinutes = positiveNumber(body.retryAfterMinutes) ??
    positiveNumber(body.retry_after_minutes);
  return {
    limit: limit ? Math.trunc(limit) : undefined,
    leaseSeconds: leaseSeconds ? Math.trunc(leaseSeconds) : undefined,
    retryAfterMinutes: retryAfterMinutes
      ? Math.trunc(retryAfterMinutes)
      : undefined,
    awaitInvocations: body.awaitInvocations === true ||
      body.await_invocations === true,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const auth = await authorizeServiceRoleRequest(req, {
    supabaseUrl,
    envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  });
  if (!auth.ok || !auth.token) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    const parsed = await req.json();
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      body = parsed as Record<string, unknown>;
    }
  } catch {
    body = {};
  }

  try {
    const supabaseAdmin = createClient(supabaseUrl, auth.token, {
      global: {
        headers: {
          Authorization: `Bearer ${auth.token}`,
          apikey: auth.token,
        },
      },
    });
    const result = await replayScanIngestion(
      supabaseAdmin,
      {
        ...parseOptions(body),
        identifyUrl: `${supabaseUrl}/functions/v1/identify-multimodal`,
        serviceRoleKey: auth.token,
        awaitInvocations: body.awaitInvocations === true ||
          body.await_invocations === true,
      },
    );

    console.log(JSON.stringify({
      event: "replay_scan_ingestion_complete",
      ...result,
      errors: result.errors.length,
      ts: new Date().toISOString(),
    }));

    return jsonResponse({ success: true, ...result }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("replay_scan_ingestion_failed", {
      error: message,
    });
    return jsonResponse({ error: message }, 500);
  }
});
