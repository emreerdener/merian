import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchScanStatusMedia } from "./db.ts";

function normalizeRequiredVideoCount(value: unknown): number {
  if (value == null) return 0;
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw new Error("required_video_count must be a non-negative integer.");
  }
  return value as number;
}

function cleanMediaUrls(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => typeof entry === "string" ? entry.trim() : "")
    .filter((entry) => entry.length > 0);
}

function capturedVideoCount(value: unknown): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      return false;
    }
    return Object.hasOwn(entry as Record<string, unknown>, "video");
  }).length;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();

    const paramError = requireParams(body, ["scan_id"]);
    if (paramError) return paramError;

    const { scan_id } = body;

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
      const row = await fetchScanStatusMedia(scan_id, user.id, supabaseAdmin);
      let exists = row?.id != null;

      if (exists && requiredVideoCount > 0) {
        const videoUrlCount = cleanMediaUrls(row?.video_storage_urls).length;
        const manifestVideoCount = capturedVideoCount(row?.captured_media);
        exists = videoUrlCount >= requiredVideoCount &&
          manifestVideoCount >= requiredVideoCount;
      }

      return jsonResponse({ status: exists ? "found" : "not_found" }, 200);
    } catch (error) {
      logStructuredError("check_scan_status_failed", {
        scan_id,
        error: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse({ error: "Internal Server Error" }, 500);
    }
  })
);
