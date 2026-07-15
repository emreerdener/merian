import { SupabaseClient } from "@supabase/supabase-js";

import { fetchCaptureUploadSessionIdsForKeys } from "./scanMediaAssets.ts";
import {
  claimScanIngestionJob,
  type ScanIngestionJobStatus,
  scanIngestionManifestChecksum,
  type ScanIngestionMediaCounts,
  type ScanIngestionMediaObjectKeys,
  scanIngestionMediaObjectKeys,
  updateScanIngestionJob,
} from "./scanIngestionJobs.ts";
import {
  recordScanIngestionIntent,
  SCAN_INGESTION_INTENT_SCHEMA_VERSION,
} from "./scanIngestionIntents.ts";

export type CompatibilityScanIngestionEndpoint =
  | "identify"
  | "identify-describe"
  | "audio-spec";

export interface CompatibilityScanIngestionTelemetry {
  timestamp?: unknown;
  gpsLatitude?: unknown;
  gpsLongitude?: unknown;
  gpsElevation?: unknown;
  semanticLocation?: unknown;
  publicLocationLabel?: unknown;
  geoprivacy?: unknown;
  weatherCondition?: unknown;
  weatherTemperatureF?: unknown;
  deviceLocale?: unknown;
  deviceTimeZone?: unknown;
  deviceRegion?: unknown;
  currentMonth?: unknown;
  timeOfDay?: unknown;
  depthScaleText?: unknown;
  zoomFactor?: unknown;
  estimatedSizeCm?: unknown;
}

export interface BuildCompatibilityScanIngestionIntentInput {
  scanId: string;
  endpoint: CompatibilityScanIngestionEndpoint;
  imageKeys?: string[];
  audioKeys?: string[];
  videoKeys?: string[];
  inlineImageCount?: number;
  inlineAudioCount?: number;
  requiredVideoCount?: number;
  videoFrameCount?: number;
  videoInferenceFrameCount?: number;
  description?: unknown;
  observationContexts?: Array<Record<string, unknown>>;
  visualMediaItems?: Array<Record<string, unknown>>;
  audioMediaItems?: Array<Record<string, unknown>>;
  mimeType?: unknown;
  telemetry?: CompatibilityScanIngestionTelemetry;
  uploadSessionIds?: string[];
}

export interface CompatibilityScanIngestionIntent {
  requestPayload: Record<string, unknown>;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  uploadSessionIds: string[];
  manifestChecksum: string;
  payloadChecksum: string;
  resumable: boolean;
  inlineMediaRedacted: boolean;
  redactedMediaCounts: Record<string, number>;
}

export interface CompatibilityScanIngestionLedgerInput
  extends BuildCompatibilityScanIngestionIntentInput {
  userId: string;
  logStructuredError?: (
    event: string,
    payload: Record<string, unknown>,
  ) => void;
}

export interface CompatibilityScanIngestionLedger {
  intent: CompatibilityScanIngestionIntent;
  mark(
    status: ScanIngestionJobStatus,
    stage: string,
    options?: {
      lastError?: string | null;
      retryAfter?: string | null;
      leaseSeconds?: number;
    },
  ): Promise<void>;
  markComplete(stage?: string): Promise<void>;
  markRetryableFailure(stage: string, error: unknown): Promise<void>;
  markTerminalFailure(stage: string, error: unknown): Promise<void>;
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

function cleanStringArray(values: string[] | undefined): string[] {
  return [
    ...new Set(
      (values ?? [])
        .map((value) => cleanString(value))
        .filter((value): value is string => value !== undefined),
    ),
  ];
}

function stripUndefined(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value
      .map(stripUndefined)
      .filter((item) => item !== undefined);
  }
  if (value && typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(value)) {
      const cleaned = stripUndefined(entryValue);
      if (cleaned !== undefined) output[key] = cleaned;
    }
    return output;
  }
  return value === undefined ? undefined : value;
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, entryValue]) => entryValue !== undefined)
      .sort(([lhs], [rhs]) => lhs.localeCompare(rhs));
    return `{${
      entries.map(([key, entryValue]) =>
        `${JSON.stringify(key)}:${stableJson(entryValue)}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(stableJson(value));
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

function retryAfterIso(minutes = 5): string {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

function positiveInteger(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

function sanitizeObjectArray(
  values: Array<Record<string, unknown>> | undefined,
): Record<string, unknown>[] {
  return (values ?? [])
    .map((value) => stripUndefined(value) as Record<string, unknown>)
    .filter((value) => Object.keys(value).length > 0);
}

function sanitizeObservationContexts(
  input: BuildCompatibilityScanIngestionIntentInput,
): Record<string, unknown>[] {
  const contexts: Record<string, unknown>[] = [];
  const description = cleanString(input.description);
  if (description) {
    contexts.push({ freeText: description });
  }

  for (const context of input.observationContexts ?? []) {
    const freeText = cleanString(context.freeText ?? context.free_text);
    const addedAt = cleanString(context.addedAt ?? context.added_at);
    if (freeText || addedAt) {
      contexts.push(stripUndefined({ freeText, addedAt }) as Record<
        string,
        unknown
      >);
    }
  }

  return contexts;
}

function sanitizeTelemetry(
  telemetry: CompatibilityScanIngestionTelemetry | undefined,
): Record<string, unknown> {
  return stripUndefined({
    timestamp: cleanString(telemetry?.timestamp),
    gpsLatitude: cleanNumber(telemetry?.gpsLatitude),
    gpsLongitude: cleanNumber(telemetry?.gpsLongitude),
    gpsElevation: cleanNumber(telemetry?.gpsElevation),
    semanticLocation: cleanString(telemetry?.semanticLocation),
    publicLocationLabel: cleanString(telemetry?.publicLocationLabel),
    geoprivacy: cleanString(telemetry?.geoprivacy),
    weatherCondition: cleanString(telemetry?.weatherCondition),
    weatherTemperatureF: cleanNumber(telemetry?.weatherTemperatureF),
    deviceLocale: cleanString(telemetry?.deviceLocale),
    deviceTimeZone: cleanString(telemetry?.deviceTimeZone),
    deviceRegion: cleanString(telemetry?.deviceRegion),
    currentMonth: cleanNumber(telemetry?.currentMonth),
    timeOfDay: cleanString(telemetry?.timeOfDay),
    depthScaleText: cleanString(telemetry?.depthScaleText),
    zoomFactor: cleanNumber(telemetry?.zoomFactor),
    estimatedSizeCm: cleanNumber(telemetry?.estimatedSizeCm),
  }) as Record<string, unknown>;
}

export async function buildCompatibilityScanIngestionIntent(
  input: BuildCompatibilityScanIngestionIntentInput,
): Promise<CompatibilityScanIngestionIntent> {
  const mediaObjectKeys = scanIngestionMediaObjectKeys({
    imageKeys: input.imageKeys,
    audioKeys: input.audioKeys,
    videoKeys: input.videoKeys,
  });
  const uploadSessionIds = cleanStringArray(input.uploadSessionIds).sort();
  const inlineImageCount = positiveInteger(input.inlineImageCount);
  const inlineAudioCount = positiveInteger(input.inlineAudioCount);
  const observationContexts = sanitizeObservationContexts(input);
  const visualMediaItems = sanitizeObjectArray(input.visualMediaItems);
  const audioMediaItems = sanitizeObjectArray(input.audioMediaItems);
  const mediaCounts: ScanIngestionMediaCounts = {
    image_count: mediaObjectKeys.image.length + inlineImageCount,
    audio_count: mediaObjectKeys.audio.length + inlineAudioCount,
    video_count: mediaObjectKeys.video.length,
    required_video_count: positiveInteger(input.requiredVideoCount),
    video_frame_count: positiveInteger(input.videoFrameCount),
    video_inference_frame_count: positiveInteger(
      input.videoInferenceFrameCount,
    ),
    has_description: observationContexts.length > 0,
  };
  const manifestChecksum = await scanIngestionManifestChecksum({
    mediaCounts,
    mediaObjectKeys,
    uploadSessionIds,
  });
  const inlineMediaRedacted = inlineImageCount > 0 || inlineAudioCount > 0;
  const redactedMediaCounts = {
    image_base64_count: inlineImageCount,
    audio_base64_count: inlineAudioCount,
  };
  const hasReplayEvidence = mediaObjectKeys.image.length > 0 ||
    mediaObjectKeys.audio.length > 0 ||
    observationContexts.length > 0;

  const requestPayload = stripUndefined({
    schemaVersion: SCAN_INGESTION_INTENT_SCHEMA_VERSION,
    clientScanId: input.scanId,
    endpoint: "identify-multimodal",
    compatibilityEndpoint: input.endpoint,
    media: {
      r2ObjectKeys: mediaObjectKeys.image,
      audioR2ObjectKeys: mediaObjectKeys.audio,
      videoR2ObjectKeys: mediaObjectKeys.video,
      videoFrameCount: positiveInteger(input.videoFrameCount),
      visualMediaItems,
      audioMediaItems,
      mimeType: cleanString(input.mimeType),
    },
    telemetry: sanitizeTelemetry(input.telemetry),
    observationContexts,
    mediaCounts,
    uploadSessionIds,
    manifestChecksum,
    redactedMediaCounts,
  }) as Record<string, unknown>;

  return {
    requestPayload,
    mediaCounts,
    mediaObjectKeys,
    uploadSessionIds,
    manifestChecksum,
    payloadChecksum: await sha256Hex(requestPayload),
    resumable: !inlineMediaRedacted && hasReplayEvidence,
    inlineMediaRedacted,
    redactedMediaCounts,
  };
}

export async function createCompatibilityScanIngestionLedger(
  input: CompatibilityScanIngestionLedgerInput,
  supabaseAdmin: SupabaseClient,
): Promise<CompatibilityScanIngestionLedger> {
  const storageKeys = [
    ...(input.imageKeys ?? []),
    ...(input.audioKeys ?? []),
    ...(input.videoKeys ?? []),
  ];
  let uploadSessionIds = cleanStringArray(input.uploadSessionIds).sort();
  if (uploadSessionIds.length === 0 && storageKeys.length > 0) {
    try {
      uploadSessionIds = await fetchCaptureUploadSessionIdsForKeys(
        {
          userId: input.userId,
          clientScanId: input.scanId,
          storageKeys,
        },
        supabaseAdmin,
      );
    } catch (error) {
      input.logStructuredError?.(
        `${input.endpoint}/scan_ingestion_upload_sessions_failed`,
        {
          user_id: input.userId,
          scan_id: input.scanId,
          error: error instanceof Error ? error.message : String(error),
        },
      );
    }
  }

  const intent = await buildCompatibilityScanIngestionIntent({
    ...input,
    uploadSessionIds,
  });

  const logUpdateFailure = (
    action: string,
    error: unknown,
    extra: Record<string, unknown> = {},
  ) => {
    input.logStructuredError?.(`${input.endpoint}/${action}`, {
      user_id: input.userId,
      scan_id: input.scanId,
      error: error instanceof Error ? error.message : String(error),
      ...extra,
    });
  };

  try {
    await claimScanIngestionJob(
      {
        scanId: input.scanId,
        userId: input.userId,
        endpoint: input.endpoint,
        mediaCounts: intent.mediaCounts,
        mediaObjectKeys: intent.mediaObjectKeys,
        uploadSessionIds: intent.uploadSessionIds,
        manifestChecksum: intent.manifestChecksum,
        leaseSeconds: 300,
      },
      supabaseAdmin,
    );
  } catch (error) {
    logUpdateFailure("scan_ingestion_job_claim_failed", error);
  }

  try {
    await recordScanIngestionIntent(
      {
        scanId: input.scanId,
        userId: input.userId,
        endpoint: input.endpoint,
        requestPayload: intent.requestPayload,
        mediaCounts: intent.mediaCounts,
        mediaObjectKeys: intent.mediaObjectKeys,
        uploadSessionIds: intent.uploadSessionIds,
        manifestChecksum: intent.manifestChecksum,
        payloadChecksum: intent.payloadChecksum,
        resumable: intent.resumable,
        inlineMediaRedacted: intent.inlineMediaRedacted,
        redactedMediaCounts: intent.redactedMediaCounts,
      },
      supabaseAdmin,
    );
  } catch (error) {
    logUpdateFailure("scan_ingestion_intent_record_failed", error);
  }

  const mark = async (
    status: ScanIngestionJobStatus,
    stage: string,
    options: {
      lastError?: string | null;
      retryAfter?: string | null;
      leaseSeconds?: number;
    } = {},
  ) => {
    try {
      await updateScanIngestionJob(
        {
          scanId: input.scanId,
          userId: input.userId,
          status,
          stage,
          lastError: options.lastError ?? null,
          retryAfter: options.retryAfter ?? null,
          leaseSeconds: options.leaseSeconds,
        },
        supabaseAdmin,
      );
    } catch (error) {
      logUpdateFailure("scan_ingestion_job_update_failed", error, {
        status,
        stage,
      });
    }
  };

  await mark("finalizing", "background_ingestion_queued", {
    leaseSeconds: 300,
  });

  return {
    intent,
    mark,
    markComplete: (stage = "scan_inserted") => mark("complete", stage),
    markRetryableFailure: (stage: string, error: unknown) =>
      mark("failed_retryable", stage, {
        lastError: error instanceof Error ? error.message : String(error),
        retryAfter: retryAfterIso(),
      }),
    markTerminalFailure: (stage: string, error: unknown) =>
      mark("failed_terminal", stage, {
        lastError: error instanceof Error ? error.message : String(error),
      }),
  };
}
