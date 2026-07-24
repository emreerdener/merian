import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { scanIngestionClientState } from "../_shared/scanIngestionJobs.ts";
import { fetchScanStatusJob, fetchScanStatusMedia } from "./db.ts";
import {
  hasRequiredVideoMedia,
  normalizeRequiredVideoCount,
} from "./status.ts";

interface ScanStatusRequest {
  scan_id: string;
  required_video_count?: unknown;
}

async function buildScanStatusResponse(
  request: ScanStatusRequest,
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const requiredVideoCount = normalizeRequiredVideoCount(
    request.required_video_count,
  );
  const row = await fetchScanStatusMedia(
    request.scan_id,
    userId,
    supabaseAdmin,
  );
  let exists = row?.id != null;

  if (exists && requiredVideoCount > 0) {
    exists = hasRequiredVideoMedia(row, requiredVideoCount);
  }

  let job = null;
  if (!exists) {
    try {
      job = await fetchScanStatusJob(request.scan_id, userId, supabaseAdmin);
    } catch (error) {
      logStructuredError("check_scan_status_job_fetch_failed", {
        scan_id: request.scan_id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  const jobState = scanIngestionClientState(job);

  return {
    scan_id: request.scan_id,
    status: exists ? "found" : "not_found",
    job_status: jobState?.status ?? null,
    job_stage: jobState?.stage ?? null,
    job_attempt_count: jobState?.attempt_count ?? null,
    retry_after: jobState?.retry_after ?? null,
    last_error: jobState?.last_error ?? null,
  };
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "standard" });
    if (body instanceof Response) return body;

    if (Array.isArray(body.scans)) {
      if (body.scans.length > 50) {
        return jsonResponse(
          { error: "A maximum of 50 scans can be checked." },
          400,
        );
      }
      const requests: ScanStatusRequest[] = [];
      for (const entry of body.scans) {
        if (!entry || typeof entry !== "object") {
          return jsonResponse({
            error: "Each scan status request must be an object.",
          }, 400);
        }
        const scanId = (entry as Record<string, unknown>).scan_id;
        if (typeof scanId !== "string" || scanId.trim().length === 0) {
          return jsonResponse(
            { error: "scan_id is required for each scan." },
            400,
          );
        }
        requests.push({
          scan_id: scanId,
          required_video_count:
            (entry as Record<string, unknown>).required_video_count,
        });
      }
      try {
        const results = [];
        for (const scanStatusRequest of requests) {
          results.push(
            await buildScanStatusResponse(
              scanStatusRequest,
              user.id,
              supabaseAdmin,
            ),
          );
        }
        return jsonResponse({ results }, 200);
      } catch (error) {
        logStructuredError("check_scan_status_bulk_failed", {
          error: error instanceof Error ? error.message : String(error),
        });
        return jsonResponse({ error: "Internal Server Error" }, 500);
      }
    }

    const paramError = requireParams(body, ["scan_id"]);
    if (paramError) return paramError;

    const scanId = body.scan_id;
    if (typeof scanId !== "string") {
      return jsonResponse({ error: "scan_id must be a string." }, 400);
    }

    let requiredVideoCount: number;
    try {
      requiredVideoCount = normalizeRequiredVideoCount(
        body.required_video_count,
      );
    } catch (error) {
      return jsonResponse({
        error: error instanceof Error ? error.message : String(error),
      }, 400);
    }

    try {
      const response = await buildScanStatusResponse(
        { scan_id: scanId, required_video_count: requiredVideoCount },
        user.id,
        supabaseAdmin,
      );
      const { scan_id: _scanId, ...singleResponse } = response;
      return jsonResponse(singleResponse, 200);
    } catch (error) {
      logStructuredError("check_scan_status_failed", {
        scan_id: scanId,
        error: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse({ error: "Internal Server Error" }, 500);
    }
  })
);
