import { createClient } from "@supabase/supabase-js";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  timingSafeCompare,
} from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import {
  parseMerianReferenceImageRefreshRequest,
  runMerianReferenceImageRefresh,
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

    const parsedRequest = parseMerianReferenceImageRefreshRequest(body);
    if (!parsedRequest.request) {
      return jsonResponse(
        {
          error: parsedRequest.error ??
            "Invalid Naturebook reference refresh request.",
        },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey,
    );

    const result = await runMerianReferenceImageRefresh(
      parsedRequest.request,
      supabaseAdmin,
    );

    console.log(JSON.stringify({
      event: "merian_reference_image_refresh_complete",
      candidate_count: result.candidate_count,
      promoted_count: result.promoted_count,
      removed_count: result.removed_count,
      species_count: result.species_count,
      dry_run: result.dry_run,
      quality_threshold: parsedRequest.request.qualityThreshold,
      species_confidence_threshold:
        parsedRequest.request.speciesConfidenceThreshold,
    }));

    return jsonResponse({ success: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logStructuredError("merian_reference_image_refresh_failed", {
      error: message,
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
