import { serveEdge } from "../_shared/edgeHandler.ts";
import { corsHeaders, publicErrorResponse } from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";

import { requestNonBiologicalScanRetentionDeletions } from "./db.ts";

const BATCH_SIZE = 500;
const MAXIMUM_GENERATIONS_PER_INVOCATION = 10_000;
const RUNTIME_BUDGET_MS = 40_000;

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serveEdge(async (req: Request) => {
  let step = "request";

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  step = "auth";
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const deadline = Date.now() + RUNTIME_BUDGET_MS;
    let requestedCount = 0;
    let runtimeDeadlineReached = false;

    step = "request_retention_deletions";
    while (requestedCount < MAXIMUM_GENERATIONS_PER_INVOCATION) {
      if (Date.now() >= deadline) {
        runtimeDeadlineReached = true;
        break;
      }

      const accepted = await requestNonBiologicalScanRetentionDeletions(
        Math.min(
          BATCH_SIZE,
          MAXIMUM_GENERATIONS_PER_INVOCATION - requestedCount,
        ),
        supabaseAdmin,
      );
      requestedCount += accepted;
      if (accepted < BATCH_SIZE) break;
    }

    console.log(JSON.stringify({
      event: "auto_purge_nonbio_requested",
      requested_count: requestedCount,
      runtime_deadline_reached: runtimeDeadlineReached,
    }));

    return jsonResponse(
      {
        success: true,
        requested_count: requestedCount,
        runtime_deadline_reached: runtimeDeadlineReached,
      },
      200,
    );
  } catch (err: unknown) {
    console.error(JSON.stringify({
      event: "auto_purge_nonbio_failed",
      step,
      error: err instanceof Error ? err.name : typeof err,
    }));
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
