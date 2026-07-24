import { createClient } from "@supabase/supabase-js";
import { normalizeLimit } from "../_shared/explore.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
  timingSafeCompare,
} from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";

serveEdge(async (req: Request) => {
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

  try {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

    const limit = normalizeLimit(body.limit, 25, 100);
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data, error } = await supabaseAdmin.rpc(
      "process_community_consensus_jobs",
      { max_jobs: limit },
    );

    if (error) {
      throw new Error(
        `Failed to process community consensus jobs: ${error.message}`,
      );
    }

    return jsonResponse({ success: true, data: data ?? [] }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    logStructuredError("community_consensus_processing_failed", {
      error: message,
    });
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
