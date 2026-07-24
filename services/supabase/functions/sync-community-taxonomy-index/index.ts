import { createClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import {
  parseCommunityTaxonomyIndexSyncRequest,
  runCommunityTaxonomyIndexSync,
} from "./db.ts";

serveEdge(async (req: Request) => {
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
    const body = await parseJsonBody<Record<string, unknown>>(req, {
      allowEmpty: true,
      limit: "small",
    });
    if (body instanceof Response) return body;

    const parsedRequest = parseCommunityTaxonomyIndexSyncRequest(body);
    if (!parsedRequest.request) {
      return jsonResponse(
        {
          error: parsedRequest.error ??
            "Invalid community taxonomy index sync request.",
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
    const result = await runCommunityTaxonomyIndexSync(
      parsedRequest.request,
      supabaseAdmin,
    );

    console.log(JSON.stringify({
      event: "community_taxonomy_index_sync_complete",
      target: result.target,
      root_gbif_taxon_key: result.root_gbif_taxon_key,
      start_offset: result.start_offset,
      imported_count: result.imported_count,
      normalized_count: result.normalized_count,
      next_offset: result.next_offset,
      dry_run: result.dry_run,
      retry: result.retry,
      refresh_coverage: result.refresh_coverage,
    }));

    return jsonResponse({ success: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("community_taxonomy_index_sync_failed", {
      error: message,
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
