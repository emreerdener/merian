import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleDataClient } from "../_shared/serviceRoleClient.ts";
import { fetchScanMediaHealth } from "./db.ts";
import { parseScanMediaHealthRequest } from "./health.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const auth = authorizeServiceRoleRequest(req, {
    envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    envSecretKeys: Deno.env.get("SUPABASE_SECRET_KEYS") ?? "",
  });
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await parseJsonBody<Record<string, unknown>>(req, {
      allowEmpty: true,
      limit: "small",
    });
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

    const supabaseAdmin = createServiceRoleDataClient(
      supabaseUrl,
      auth.serverApiKey,
    );
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
