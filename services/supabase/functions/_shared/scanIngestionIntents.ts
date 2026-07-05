import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import type {
  AudioMediaItemDTO,
  MultimodalPayload,
  ObservationContextDTO,
  VisualMediaItemDTO,
} from "./identify/types.ts";
import type {
  ScanIngestionMediaCounts,
  ScanIngestionMediaObjectKeys,
} from "./scanIngestionJobs.ts";

export const SCAN_INGESTION_INTENT_SCHEMA_VERSION = 1;

export interface SanitizedScanIngestionIntent {
  payload: Record<string, unknown>;
  payloadChecksum: string;
  resumable: boolean;
  inlineMediaRedacted: boolean;
  redactedMediaCounts: Record<string, number>;
}

export interface BuildScanIngestionIntentInput {
  scanId: string;
  payload: MultimodalPayload;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  uploadSessionIds?: string[];
  manifestChecksum?: string | null;
  visualMediaItems?: VisualMediaItemDTO[];
  audioMediaItems?: AudioMediaItemDTO[];
  normalizedTelemetry?: Record<string, unknown>;
}

export interface RecordScanIngestionIntentInput {
  scanId: string;
  userId: string;
  endpoint: string;
  requestPayload: Record<string, unknown>;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  uploadSessionIds?: string[];
  manifestChecksum?: string | null;
  payloadChecksum?: string | null;
  resumable: boolean;
  inlineMediaRedacted: boolean;
  redactedMediaCounts: Record<string, number>;
  payloadSchemaVersion?: number;
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

function cleanBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
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

function sanitizeObservationContexts(
  contexts: ObservationContextDTO[] | undefined,
): Record<string, unknown>[] {
  return (contexts ?? [])
    .map((context) => {
      const freeText = cleanString(context.freeText ?? context.free_text);
      const addedAt = cleanString(context.addedAt ?? context.added_at);
      return stripUndefined({
        freeText,
        addedAt,
      }) as Record<string, unknown>;
    })
    .filter((context) => Object.keys(context).length > 0);
}

function sanitizeVisualMediaItems(
  items: VisualMediaItemDTO[] | undefined,
): Record<string, unknown>[] {
  return (items ?? [])
    .map((item) =>
      stripUndefined({
        kind: cleanString(item.kind),
        sourceIndex: cleanNumber(item.sourceIndex ?? item.source_index),
        clipIndex: cleanNumber(item.clipIndex ?? item.clip_index),
        frameIndex: cleanNumber(item.frameIndex ?? item.frame_index),
      }) as Record<string, unknown>
    )
    .filter((item) => Object.keys(item).length > 0);
}

function sanitizeAudioMediaItems(
  items: AudioMediaItemDTO[] | undefined,
): Record<string, unknown>[] {
  return (items ?? [])
    .map((item) =>
      stripUndefined({
        kind: cleanString(item.kind),
        sourceIndex: cleanNumber(item.sourceIndex ?? item.source_index),
        clipIndex: cleanNumber(item.clipIndex ?? item.clip_index),
      }) as Record<string, unknown>
    )
    .filter((item) => Object.keys(item).length > 0);
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

export async function buildScanIngestionIntent(
  input: BuildScanIngestionIntentInput,
): Promise<SanitizedScanIngestionIntent> {
  const payload = input.payload;
  const inlineImageCount = Array.isArray(payload.imageBase64s)
    ? payload.imageBase64s.length
    : 0;
  const inlineAudioCount = Array.isArray(payload.audioBase64s)
    ? payload.audioBase64s.length
    : 0;
  const inlineMediaRedacted = inlineImageCount > 0 || inlineAudioCount > 0;
  const redactedMediaCounts = {
    image_base64_count: inlineImageCount,
    audio_base64_count: inlineAudioCount,
  };

  const telemetry = stripUndefined({
    timestamp: cleanString(payload.timestamp),
    gpsLatitude: cleanNumber(
      input.normalizedTelemetry?.gpsLatitude ?? payload.gpsLatitude ??
        payload.gps_latitude,
    ),
    gpsLongitude: cleanNumber(
      input.normalizedTelemetry?.gpsLongitude ?? payload.gpsLongitude ??
        payload.gps_longitude,
    ),
    gpsElevation: cleanNumber(
      input.normalizedTelemetry?.gpsElevation ?? payload.gpsElevation ??
        payload.gps_elevation,
    ),
    semanticLocation: cleanString(
      input.normalizedTelemetry?.semanticLocation ?? payload.semanticLocation ??
        payload.semantic_location,
    ),
    publicLocationLabel: cleanString(
      input.normalizedTelemetry?.publicLocationLabel ??
        payload.publicLocationLabel ?? payload.public_location_label,
    ),
    geoprivacy: cleanString(
      input.normalizedTelemetry?.geoprivacy ?? payload.geoprivacy,
    ),
    weatherCondition: cleanString(
      input.normalizedTelemetry?.weatherCondition ?? payload.weatherCondition ??
        payload.weather_condition,
    ),
    weatherTemperatureF: cleanNumber(
      input.normalizedTelemetry?.weatherTemperatureF ??
        payload.weatherTemperatureF ?? payload.weather_temperature_f,
    ),
    deviceLocale: cleanString(
      input.normalizedTelemetry?.deviceLocale ?? payload.deviceLocale ??
        payload.device_locale,
    ),
    deviceTimeZone: cleanString(
      input.normalizedTelemetry?.deviceTimeZone ?? payload.deviceTimeZone ??
        payload.device_time_zone,
    ),
    deviceRegion: cleanString(
      input.normalizedTelemetry?.deviceRegion ?? payload.deviceRegion ??
        payload.device_region,
    ),
    currentMonth: cleanNumber(
      input.normalizedTelemetry?.currentMonth ?? payload.currentMonth ??
        payload.current_month,
    ),
    timeOfDay: cleanString(
      input.normalizedTelemetry?.timeOfDay ?? payload.timeOfDay ??
        payload.time_of_day,
    ),
    depthScaleText: cleanString(
      input.normalizedTelemetry?.depthScaleText ?? payload.depthScaleText ??
        payload.depth_scale_text,
    ),
    zoomFactor: cleanNumber(
      input.normalizedTelemetry?.zoomFactor ?? payload.zoomFactor,
    ),
    estimatedSizeCm: cleanNumber(
      input.normalizedTelemetry?.estimatedSizeCm ?? payload.estimatedSizeCm ??
        payload.estimated_size_cm,
    ),
    isIpad: cleanBoolean(payload.isIpad),
  }) as Record<string, unknown>;

  const requestPayload = stripUndefined({
    schemaVersion: SCAN_INGESTION_INTENT_SCHEMA_VERSION,
    clientScanId: input.scanId,
    endpoint: "identify-multimodal",
    media: {
      r2ObjectKeys: cleanStringArray(input.mediaObjectKeys.image),
      audioR2ObjectKeys: cleanStringArray(input.mediaObjectKeys.audio),
      videoR2ObjectKeys: cleanStringArray(input.mediaObjectKeys.video),
      videoFrameCount: cleanNumber(payload.videoFrameCount),
      visualMediaItems: sanitizeVisualMediaItems(
        input.visualMediaItems ?? payload.visualMediaItems ??
          payload.visual_media_items,
      ),
      audioMediaItems: sanitizeAudioMediaItems(
        input.audioMediaItems ?? payload.audioMediaItems ??
          payload.audio_media_items,
      ),
      mimeType: cleanString(payload.mimeType),
    },
    telemetry,
    observationContexts: sanitizeObservationContexts(
      payload.observation_contexts,
    ),
    mediaCounts: input.mediaCounts,
    uploadSessionIds: cleanStringArray(input.uploadSessionIds).sort(),
    manifestChecksum: cleanString(input.manifestChecksum ?? undefined),
    redactedMediaCounts,
  }) as Record<string, unknown>;

  return {
    payload: requestPayload,
    payloadChecksum: await sha256Hex(requestPayload),
    resumable: !inlineMediaRedacted,
    inlineMediaRedacted,
    redactedMediaCounts,
  };
}

export async function recordScanIngestionIntent(
  input: RecordScanIngestionIntentInput,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc("record_scan_ingestion_intent", {
    p_scan_id: input.scanId,
    p_user_id: input.userId,
    p_endpoint: input.endpoint,
    p_request_payload: input.requestPayload,
    p_media_counts: input.mediaCounts,
    p_media_object_keys: input.mediaObjectKeys,
    p_upload_session_ids: input.uploadSessionIds ?? [],
    p_manifest_checksum: input.manifestChecksum ?? null,
    p_payload_checksum: input.payloadChecksum ?? null,
    p_resumable: input.resumable,
    p_inline_media_redacted: input.inlineMediaRedacted,
    p_redacted_media_counts: input.redactedMediaCounts,
    p_payload_schema_version: input.payloadSchemaVersion ??
      SCAN_INGESTION_INTENT_SCHEMA_VERSION,
  });

  if (error) {
    throw new Error(`recordScanIngestionIntent: ${error.message}`);
  }
}
