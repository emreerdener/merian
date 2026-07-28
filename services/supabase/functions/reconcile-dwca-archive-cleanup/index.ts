import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
  requestIdFor,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { reconcileDwcaArchiveCleanup } from "./worker.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return publicErrorResponse(
      req,
      405,
      "method_not_allowed",
      "Method not allowed.",
      { extraHeaders: { Allow: "POST" } },
    );
  }
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return publicErrorResponse(req, 401, "unauthorized", "Unauthorized.");
  }

  const requestId = requestIdFor(req);
  try {
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const result = await reconcileDwcaArchiveCleanup(supabaseAdmin);
    const event = JSON.stringify({
      event: "dwca_archive_cleanup_health",
      request_id: requestId,
      status: result.healthStatus,
      claimed: result.claimed,
      completed: result.completed,
      deferred: result.deferred,
      runtime_deadline_reached: result.runtimeDeadlineReached,
      ...result.health,
      ts: new Date().toISOString(),
    });
    if (result.healthStatus === "critical") {
      console.error(event);
    } else if (result.healthStatus === "warning") {
      console.warn(event);
    } else {
      console.log(event);
    }
    return jsonResponse(
      {
        success: true,
        claimed: result.claimed,
        completed: result.completed,
        deferred: result.deferred,
        health_status: result.healthStatus,
      },
      200,
      {
        "Cache-Control": "private, no-store",
        "X-Request-ID": requestId,
      },
    );
  } catch (error) {
    console.error(JSON.stringify({
      event: "dwca_archive_cleanup_failed",
      request_id: requestId,
      error: error instanceof Error ? error.name : typeof error,
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      503,
      "cleanup_unavailable",
      "Archive cleanup is temporarily unavailable.",
    );
  }
});
