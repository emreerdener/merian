import { normalizeLimit } from "../_shared/explore.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

    const limit = normalizeLimit(body.limit, 25, 100);
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
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
