import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import {
  fetchCommunityTaxonomyStatus,
  parseCommunityTaxonomyStatusRequest,
} from "./db.ts";

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
    console.warn(JSON.stringify({
      event: "community_taxonomy_status_auth_denied",
      reason: auth.reason,
      ts: new Date().toISOString(),
    }));
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await parseJsonBody<Record<string, unknown>>(req, {
      allowEmpty: true,
      limit: "small",
    });
    if (body instanceof Response) return body;

    const parsedRequest = parseCommunityTaxonomyStatusRequest(body);
    if (!parsedRequest.request) {
      return jsonResponse(
        {
          error: parsedRequest.error ??
            "Invalid community taxonomy status request.",
        },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createServiceRoleClient(
      supabaseUrl,
      auth.serverApiKey,
    );
    const status = await fetchCommunityTaxonomyStatus(
      parsedRequest.request,
      supabaseAdmin,
    );

    console.log(JSON.stringify({
      event: "community_taxonomy_status_complete",
      import_run_limit: parsedRequest.request.importRunLimit,
      job_limit: parsedRequest.request.jobLimit,
      view: parsedRequest.request.view,
      target: parsedRequest.request.target,
      active_taxonomy_id: status.active_taxonomy?.id ?? null,
      queued_job_groups: status.enrichment_jobs.counts.length,
      coverage_targets: status.coverage_targets.length,
    }));

    return jsonResponse({ success: true, ...status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("community_taxonomy_status_failed", {
      error: message,
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
