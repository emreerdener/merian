import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
  requestIdFor,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { fetchDwcaExportReleaseState } from "../_shared/dwcaReleaseState.ts";
import { ExportWorkerError } from "./types.ts";
import { drainExportJobs, type ExportDrainStep } from "./drain.ts";

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

  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
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
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const releaseState = await fetchDwcaExportReleaseState(supabaseAdmin);
    if (!releaseState.enabled) {
      console.log(JSON.stringify({
        event: "dwca_export_dispatch_disabled",
        request_id: requestId,
        ts: new Date().toISOString(),
      }));
      return jsonResponse(
        {
          success: true,
          request_id: requestId,
          disposition: "disabled",
          release: { enabled: false },
        },
        200,
        { "Cache-Control": "private, no-store" },
      );
    }
    const result = await drainExportJobs(
      supabaseAdmin,
      typeof requestedJobId === "string" ? requestedJobId : null,
      {
        onStep(step: ExportDrainStep, error?: unknown) {
          const event = JSON.stringify({
            event: "dwca_export_step_complete",
            request_id: requestId,
            job_id: step.jobId,
            disposition: step.disposition,
            phase: step.phase,
            failure_code: step.failureCode,
            error: error instanceof Error ? error.message : error,
            cause: error instanceof Error && error.cause instanceof Error
              ? error.cause.message
              : undefined,
            ts: new Date().toISOString(),
          });
          if (step.disposition === "failed") {
            console.warn(event);
          } else {
            console.log(event);
          }
        },
      },
    );
    const healthEvent = JSON.stringify({
      event: "dwca_export_queue_health",
      request_id: requestId,
      status: result.healthStatus,
      targeted_wakeup: result.targetedWakeup,
      attempted_steps: result.attemptedSteps,
      advanced_steps: result.advancedSteps,
      completed_jobs: result.completedJobs,
      failed_steps: result.failedSteps,
      discovery_waves: result.discoveryWaves,
      queue_drained: result.queueDrained,
      runtime_deadline_reached: result.runtimeDeadlineReached,
      step_limit_reached: result.stepLimitReached,
      backlog_count: result.health.backlogCount,
      due_count: result.health.dueCount,
      active_claim_count: result.health.activeClaimCount,
      expired_claim_count: result.health.expiredClaimCount,
      oldest_due_age_seconds: result.health.oldestDueAgeSeconds,
      generated_at: result.health.generatedAt,
      elapsed_milliseconds: result.elapsedMilliseconds,
      ts: new Date().toISOString(),
    });
    if (result.healthStatus === "critical") {
      console.error(healthEvent);
    } else if (result.healthStatus === "warning") {
      console.warn(healthEvent);
    } else {
      console.log(healthEvent);
    }

    return jsonResponse(
      {
        success: true,
        request_id: requestId,
        disposition: result.attemptedSteps > 0 ? "processed" : "idle",
        drain: {
          targeted_wakeup: result.targetedWakeup,
          attempted_steps: result.attemptedSteps,
          advanced_steps: result.advancedSteps,
          completed_jobs: result.completedJobs,
          not_claimed_steps: result.notClaimedSteps,
          failed_steps: result.failedSteps,
          discovery_waves: result.discoveryWaves,
          queue_drained: result.queueDrained,
          runtime_deadline_reached: result.runtimeDeadlineReached,
          step_limit_reached: result.stepLimitReached,
          elapsed_milliseconds: result.elapsedMilliseconds,
        },
        health: {
          status: result.healthStatus,
          backlog_count: result.health.backlogCount,
          due_count: result.health.dueCount,
          active_claim_count: result.health.activeClaimCount,
          expired_claim_count: result.health.expiredClaimCount,
          oldest_due_at: result.health.oldestDueAt,
          oldest_due_age_seconds: result.health.oldestDueAgeSeconds,
          generated_at: result.health.generatedAt,
        },
        results: result.steps.map((step) => ({
          job_id: step.jobId,
          disposition: step.disposition,
          phase: step.phase,
          failure_code: step.failureCode,
        })),
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
