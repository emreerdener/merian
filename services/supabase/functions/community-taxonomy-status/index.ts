import { createClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import {
  fetchCommunityTaxonomyStatus,
  parseCommunityTaxonomyStatusRequest,
} from "./db.ts";

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

    const supabaseAdmin = createClient(
      supabaseUrl,
      auth.token,
      {
        global: {
          headers: {
            Authorization: `Bearer ${auth.token}`,
            apikey: auth.token,
          },
        },
      },
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
