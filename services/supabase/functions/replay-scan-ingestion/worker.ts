import { SupabaseClient } from "@supabase/supabase-js";

import { logStructuredError, runBackground } from "../_shared/edgeHandler.ts";
import {
  claimReplayableScanIngestionJobs,
  fetchReplayScans,
  markReplayDispatchFailure,
  markReplayJobComplete,
  type ReplayableScanIngestionRow,
  type ReplayScanRow,
} from "./db.ts";

export const DEFAULT_REPLAY_LIMIT = 5;
export const MAX_REPLAY_LIMIT = 50;
export const DEFAULT_REPLAY_LEASE_SECONDS = 300;
export const DEFAULT_REPLAY_RETRY_AFTER_MINUTES = 5;

export interface ReplayScanIngestionOptions {
  limit?: number;
  leaseSeconds?: number;
  retryAfterMinutes?: number;
  identifyUrl?: string;
  serviceRoleKey?: string;
  awaitInvocations?: boolean;
}

export interface ReplayScanIngestionResult {
  claimed: number;
  dispatched: number;
  completedExisting: number;
  skippedExistingIncomplete: number;
  failedDispatches: number;
  errors: Array<{
    scanId?: string;
    userId?: string;
    reason: string;
  }>;
}

interface ReplayDependencies {
  claimJobs?: typeof claimReplayableScanIngestionJobs;
  fetchScans?: typeof fetchReplayScans;
  markComplete?: typeof markReplayJobComplete;
  markFailure?: typeof markReplayDispatchFailure;
  invokeIdentify?: typeof invokeIdentifyMultimodalReplay;
}

function clampInteger(
  value: number | undefined,
  fallback: number,
  min: number,
  max: number,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(Math.trunc(value), max));
}

function cleanString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function cleanNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function cleanStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => cleanString(item))
        .filter((item): item is string => item !== undefined),
    ),
  ];
}

function cleanObjectArray(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is Record<string, unknown> =>
    item != null && typeof item === "object" && !Array.isArray(item)
  );
}

function mediaPayload(value: Record<string, unknown>): Record<string, unknown> {
  const media = value.media;
  return media != null && typeof media === "object" && !Array.isArray(media)
    ? media as Record<string, unknown>
    : {};
}

function telemetryPayload(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const telemetry = value.telemetry;
  return telemetry != null && typeof telemetry === "object" &&
      !Array.isArray(telemetry)
    ? telemetry as Record<string, unknown>
    : {};
}

function stripUndefined(
  value: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(value).filter(([, entryValue]) => entryValue !== undefined),
  );
}

export function buildReplayIdentifyPayload(
  row: ReplayableScanIngestionRow,
): Record<string, unknown> {
  const requestPayload = row.request_payload ?? {};
  const media = mediaPayload(requestPayload);
  const telemetry = telemetryPayload(requestPayload);
  const observationContexts = cleanObjectArray(
    requestPayload.observationContexts,
  );

  return stripUndefined({
    user_id: row.user_id,
    client_scan_id: cleanString(requestPayload.clientScanId) ?? row.scan_id,
    r2ObjectKeys: cleanStringArray(media.r2ObjectKeys),
    audioR2ObjectKeys: cleanStringArray(media.audioR2ObjectKeys),
    videoR2ObjectKeys: cleanStringArray(media.videoR2ObjectKeys),
    videoFrameCount: cleanNumber(media.videoFrameCount),
    visualMediaItems: cleanObjectArray(media.visualMediaItems),
    audioMediaItems: cleanObjectArray(media.audioMediaItems),
    mimeType: cleanString(media.mimeType),
    observation_contexts: observationContexts,
    timestamp: cleanString(telemetry.timestamp),
    gpsLatitude: cleanNumber(telemetry.gpsLatitude),
    gpsLongitude: cleanNumber(telemetry.gpsLongitude),
    gpsElevation: cleanNumber(telemetry.gpsElevation),
    semanticLocation: cleanString(telemetry.semanticLocation),
    publicLocationLabel: cleanString(telemetry.publicLocationLabel),
    geoprivacy: cleanString(telemetry.geoprivacy),
    weatherCondition: cleanString(telemetry.weatherCondition),
    weatherTemperatureF: cleanNumber(telemetry.weatherTemperatureF),
    deviceLocale: cleanString(telemetry.deviceLocale),
    deviceTimeZone: cleanString(telemetry.deviceTimeZone),
    deviceRegion: cleanString(telemetry.deviceRegion),
    currentMonth: cleanNumber(telemetry.currentMonth),
    timeOfDay: cleanString(telemetry.timeOfDay),
    depthScaleText: cleanString(telemetry.depthScaleText),
    zoomFactor: cleanNumber(telemetry.zoomFactor),
    estimated_size_cm: cleanNumber(telemetry.estimatedSizeCm),
  });
}

function payloadHasEvidence(payload: Record<string, unknown>): boolean {
  return cleanStringArray(payload.r2ObjectKeys).length > 0 ||
    cleanStringArray(payload.audioR2ObjectKeys).length > 0 ||
    cleanStringArray(payload.videoR2ObjectKeys).length > 0 ||
    cleanObjectArray(payload.observation_contexts).some((context) =>
      cleanString(context.freeText ?? context.free_text) != null
    );
}

function requiredVideoCount(row: ReplayableScanIngestionRow): number {
  const value = row.media_counts?.required_video_count;
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

function capturedMediaVideoCount(value: unknown[] | null | undefined): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((item) =>
    item != null &&
    typeof item === "object" &&
    !Array.isArray(item) &&
    Object.hasOwn(item as Record<string, unknown>, "video")
  ).length;
}

function scanMediaIsComplete(
  scan: ReplayScanRow,
  requiredVideos: number,
): boolean {
  if (requiredVideos <= 0) return true;
  const videoUrls = (scan.video_storage_urls ?? [])
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
  return videoUrls.length >= requiredVideos &&
    capturedMediaVideoCount(scan.captured_media) >= requiredVideos;
}

function replayRetryAfterIso(minutes: number): string {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

function scanMapById(scans: ReplayScanRow[]): Map<string, ReplayScanRow> {
  return new Map(scans.map((scan) => [scan.id, scan]));
}

export async function invokeIdentifyMultimodalReplay(input: {
  identifyUrl: string;
  serviceRoleKey: string;
  payload: Record<string, unknown>;
  userId: string;
}): Promise<void> {
  const response = await fetch(input.identifyUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${input.serviceRoleKey}`,
      "apikey": input.serviceRoleKey,
      "X-Merian-Internal-Replay": "scan-ingestion",
      "X-Merian-Replay-User-Id": input.userId,
    },
    body: JSON.stringify(input.payload),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(
      `identify-multimodal replay failed: ${response.status} ${text}`.slice(
        0,
        500,
      ),
    );
  }
}

async function dispatchRow(
  row: ReplayableScanIngestionRow,
  supabaseAdmin: SupabaseClient,
  options: {
    identifyUrl: string;
    serviceRoleKey: string;
    retryAfterMinutes: number;
  },
  dependencies: Required<
    Pick<ReplayDependencies, "markFailure" | "invokeIdentify">
  >,
): Promise<void> {
  const payload = buildReplayIdentifyPayload(row);
  if (!payloadHasEvidence(payload)) {
    await dependencies.markFailure(
      {
        scanId: row.scan_id,
        userId: row.user_id,
        stage: "server_replay_payload_invalid",
        errorMessage: "Replay payload does not contain media or description.",
        retryAfterIso: null,
        terminal: true,
      },
      supabaseAdmin,
    );
    throw new Error("Replay payload does not contain media or description.");
  }

  try {
    await dependencies.invokeIdentify({
      identifyUrl: options.identifyUrl,
      serviceRoleKey: options.serviceRoleKey,
      payload,
      userId: row.user_id,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await dependencies.markFailure(
      {
        scanId: row.scan_id,
        userId: row.user_id,
        stage: "server_replay_dispatch_failed",
        errorMessage: message,
        retryAfterIso: replayRetryAfterIso(options.retryAfterMinutes),
      },
      supabaseAdmin,
    );
    throw error;
  }
}

export async function replayScanIngestion(
  supabaseAdmin: SupabaseClient,
  options: ReplayScanIngestionOptions = {},
  dependencies: ReplayDependencies = {},
): Promise<ReplayScanIngestionResult> {
  const limit = clampInteger(
    options.limit,
    DEFAULT_REPLAY_LIMIT,
    1,
    MAX_REPLAY_LIMIT,
  );
  const leaseSeconds = clampInteger(
    options.leaseSeconds,
    DEFAULT_REPLAY_LEASE_SECONDS,
    30,
    30 * 60,
  );
  const retryAfterMinutes = clampInteger(
    options.retryAfterMinutes,
    DEFAULT_REPLAY_RETRY_AFTER_MINUTES,
    1,
    24 * 60,
  );
  const identifyUrl = options.identifyUrl ??
    `${Deno.env.get("SUPABASE_URL") ?? ""}/functions/v1/identify-multimodal`;
  const serviceRoleKey = options.serviceRoleKey ??
    (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const claimJobs = dependencies.claimJobs ?? claimReplayableScanIngestionJobs;
  const fetchScans = dependencies.fetchScans ?? fetchReplayScans;
  const markComplete = dependencies.markComplete ?? markReplayJobComplete;
  const markFailure = dependencies.markFailure ?? markReplayDispatchFailure;
  const invokeIdentify = dependencies.invokeIdentify ??
    invokeIdentifyMultimodalReplay;

  const result: ReplayScanIngestionResult = {
    claimed: 0,
    dispatched: 0,
    completedExisting: 0,
    skippedExistingIncomplete: 0,
    failedDispatches: 0,
    errors: [],
  };

  if (!identifyUrl || !serviceRoleKey) {
    throw new Error("Missing identify URL or service role key for replay.");
  }

  const rows = await claimJobs({ limit, leaseSeconds }, supabaseAdmin);
  result.claimed = rows.length;
  if (rows.length === 0) return result;

  const scansById = scanMapById(
    await fetchScans(rows.map((row) => row.scan_id), supabaseAdmin),
  );
  const dispatchPromises: Promise<void>[] = [];

  for (const row of rows) {
    const existingScan = scansById.get(row.scan_id);
    if (existingScan) {
      const requiredVideos = requiredVideoCount(row);
      if (existingScan.user_id === row.user_id) {
        if (scanMediaIsComplete(existingScan, requiredVideos)) {
          await markComplete(
            {
              scanId: row.scan_id,
              userId: row.user_id,
              stage: "server_replay_found_existing_scan",
            },
            supabaseAdmin,
          );
          result.completedExisting++;
          continue;
        }

        await markFailure(
          {
            scanId: row.scan_id,
            userId: row.user_id,
            stage: "server_replay_existing_scan_media_incomplete",
            errorMessage:
              "Cloud scan row exists but required media is incomplete; reconciliation must repair it.",
            retryAfterIso: replayRetryAfterIso(retryAfterMinutes),
          },
          supabaseAdmin,
        );
        result.skippedExistingIncomplete++;
        continue;
      }
    }

    result.dispatched++;
    const promise = dispatchRow(
      row,
      supabaseAdmin,
      { identifyUrl, serviceRoleKey, retryAfterMinutes },
      { markFailure, invokeIdentify },
    ).catch((error) => {
      result.failedDispatches++;
      result.errors.push({
        scanId: row.scan_id,
        userId: row.user_id,
        reason: error instanceof Error ? error.message : String(error),
      });
      logStructuredError("replay_scan_ingestion_dispatch_failed", {
        scan_id: row.scan_id,
        user_id: row.user_id,
        error: error instanceof Error ? error.message : String(error),
      });
    });
    dispatchPromises.push(promise);
  }

  if (options.awaitInvocations === false) {
    runBackground(Promise.allSettled(dispatchPromises).then(() => {}));
  } else {
    await Promise.allSettled(dispatchPromises);
  }

  return result;
}
