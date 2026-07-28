import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
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
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
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

    const supabaseAdmin = createServiceRoleClient(
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
      pending_scan_deletions: report.counts.pending_scan_deletions,
      processing_scan_deletions: report.counts.processing_scan_deletions,
      expired_scan_deletion_leases: report.counts.expired_scan_deletion_leases,
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
