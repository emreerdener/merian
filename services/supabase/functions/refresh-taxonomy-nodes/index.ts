import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";

function normalizeSourceRevision(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new Error("source_revision must be a string.");
  }

  const trimmed = value.trim().replace(/\s+/g, "-");
  if (trimmed.length === 0) return null;
  if (trimmed.length > 120) {
    throw new Error("source_revision must be 120 characters or fewer.");
  }

  return trimmed;
}

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

    const sourceRevision = normalizeSourceRevision(body.source_revision);
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );

    const { data, error } = await supabaseAdmin.rpc(
      "refresh_taxonomy_nodes_from_species_dictionary",
      {
        target_source_revision: sourceRevision,
        activate_version: true,
      },
    );

    if (error) {
      throw new Error(`Failed to refresh taxonomy nodes: ${error.message}`);
    }

    return jsonResponse({ success: true, data }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error(JSON.stringify({
      event: "taxonomy_node_refresh_failed",
      error: message,
    }));
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
