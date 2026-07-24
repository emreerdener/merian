import { createClient } from "@supabase/supabase-js";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  timingSafeCompare,
} from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import {
  parseSpeciesModelContentRefreshRequest,
  runSpeciesModelContentRefresh,
} from "./db.ts";

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
  if (!serviceRoleKey || !timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await parseJsonBody<Record<string, unknown>>(req, {
      allowEmpty: true,
      limit: "small",
    });
    if (body instanceof Response) return body;

    const parsedRequest = parseSpeciesModelContentRefreshRequest(body);
    if (!parsedRequest.request) {
      return jsonResponse(
        {
          error: parsedRequest.error ??
            "Invalid species model content refresh request.",
        },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey,
    );

    const result = await runSpeciesModelContentRefresh(
      parsedRequest.request,
      supabaseAdmin,
    );

    console.log(JSON.stringify({
      event: "species_model_content_refresh_complete",
      queued_count: result.queued_count,
      refreshed_count: result.refreshed_count,
      no_data_count: result.no_data_count,
      failed_count: result.failed_count,
      dry_run: result.dry_run,
      content_groups: parsedRequest.request.contentGroups ?? null,
    }));

    return jsonResponse({ success: result.failed_count === 0, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("species_model_content_refresh_failed", {
      error: message,
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
