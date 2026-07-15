import { createClient } from "@supabase/supabase-js";

import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import { fetchScanMediaHealth } from "./db.ts";
import { parseScanMediaHealthRequest } from "./health.ts";

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

  try {
    const body = await parseOptionalJsonObjectBody(req);
    if (body instanceof Response) return body;

    const parsedRequest = parseScanMediaHealthRequest(body);
    if (!parsedRequest.request) {
      return jsonResponse(
        {
          error: parsedRequest.error ?? "Invalid scan media health request.",
        },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, auth.token, {
      global: {
        headers: {
          Authorization: `Bearer ${auth.token}`,
          apikey: auth.token,
        },
      },
    });
    const report = await fetchScanMediaHealth(
      parsedRequest.request,
      supabaseAdmin,
    );

    console.log(JSON.stringify({
      event: "scan_media_health_complete",
      status: report.status,
      issues: report.counts.issues,
      critical_issues: report.counts.critical_issues,
      warning_issues: report.counts.warning_issues,
      stale_capture_upload_assets: report.counts.stale_capture_upload_assets,
      failed_assets: report.counts.failed_assets,
      recent_scans_checked: report.counts.recent_scans_checked,
      ts: report.generated_at,
    }));

    return jsonResponse({ success: true, ...report });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("scan_media_health_failed", {
      error: message,
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});

async function parseOptionalJsonObjectBody(
  req: Request,
): Promise<Record<string, unknown> | Response> {
  const text = await req.text();
  if (text.trim().length === 0) return {};

  try {
    const body = JSON.parse(text);
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
    return jsonResponse({ error: "JSON body must be an object." }, 400);
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
}
