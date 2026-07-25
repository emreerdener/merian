import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
  requestIdFor,
  timingSafeCompare,
} from "../_shared/http.ts";
import { ExportWorkerError } from "./types.ts";
import { fetchDueExportJobIds } from "./db.ts";
import { processExportJobStep } from "./worker.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
    );
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const providedAuthorization = req.headers.get("Authorization") ?? "";
  if (
    !serviceKey ||
    !timingSafeCompare(
      providedAuthorization,
      `Bearer ${serviceKey}`,
    )
  ) {
    return publicErrorResponse(
      req,
      401,
      "unauthorized",
      "Unauthorized.",
    );
  }

  const payload = await parseJsonBody(req, { limit: "small" });
  if (payload instanceof Response) return payload;
  const requestedJobId = payload.job_id;
  if (
    requestedJobId !== undefined &&
    (typeof requestedJobId !== "string" ||
      !UUID_PATTERN.test(requestedJobId))
  ) {
    return publicErrorResponse(
      req,
      400,
      "invalid_job_id",
      "job_id must be a valid UUID when provided.",
    );
  }

  const requestId = requestIdFor(req);
  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      },
    );
    const jobIds = typeof requestedJobId === "string"
      ? [requestedJobId]
      : await fetchDueExportJobIds(supabaseAdmin, 1);
    const results = [];
    for (const jobId of jobIds) {
      const result = await processExportJobStep(jobId, supabaseAdmin);
      results.push({ job_id: jobId, ...result });
      console.log(JSON.stringify({
        event: "dwca_export_step_complete",
        request_id: requestId,
        job_id: jobId,
        ...result,
        ts: new Date().toISOString(),
      }));
    }

    return jsonResponse(
      {
        success: true,
        request_id: requestId,
        disposition: jobIds.length > 0 ? "processed" : "idle",
        results,
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    const failure = error instanceof ExportWorkerError
      ? error
      : new ExportWorkerError(
        "archive_generation_failed",
        "The export worker failed unexpectedly.",
        true,
        { cause: error },
      );
    console.error(JSON.stringify({
      event: "dwca_export_dispatch_failed",
      request_id: requestId,
      job_id: requestedJobId,
      failure_code: failure.code,
      error: failure.message,
      cause: failure.cause instanceof Error
        ? failure.cause.message
        : failure.cause,
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      500,
      "export_processing_failed",
      "The export could not be processed.",
    );
  }
});
