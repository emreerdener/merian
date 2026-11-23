import { buildScanIngestionIntent } from "../scanIngestionIntents.ts";
import type { MultimodalPayload } from "../identify/types.ts";
import type { ScanIngestionMediaCounts } from "../scanIngestionJobs.ts";
import { invalidHistory } from "./contract.ts";
import { initialCaptureAudioStageRequest } from "./initialCaptureAudioStaging.ts";
import {
  initialCapturePlanValue,
  type InitialEvidenceCapturePlan,
  parseInitialEvidenceCapturePlan,
} from "./initialEvidenceCapturePlan.ts";
import { type InitialEvidenceManifest } from "./initialEvidenceManifest.ts";
import { initialRetentionRequest } from "./initialEvidenceRetention.ts";
import { evidenceDigest } from "./evidence.ts";

export const PRIVATE_CAPTURE_INTENT_SCHEMA_VERSION = 4;
export function privateCaptureMediaCounts(
  manifest: InitialEvidenceManifest,
): ScanIngestionMediaCounts {
  let photos = 0, audio = 0, videos = 0, frames = 0, description = false;
  for (const item of manifest.items) {
    if (item.kind === "image") photos++;
    else if (item.kind === "audio") audio++;
    else if (item.kind === "description") description = true;
    else {
      videos++;
      frames += item.frames.length;
      if (item.audio) audio++;
    }
  }
  return {
    image_count: photos,
    audio_count: audio,
    video_count: videos,
    required_video_count: videos,
    video_frame_count: frames,
    video_inference_frame_count: frames,
    has_description: description,
  };
}

/** Separate intent arm: V3 remains unchanged. This builds metadata, not a stage
 * readiness proof. Existing begin repeats exact ready graph checks atomically.
 * The caller supplies only actual recovered DSP output in the final request. */
export async function buildPrivateCaptureIntent(input: {
  plan: InitialEvidenceCapturePlan;
  initialEvidence: unknown;
  payload: MultimodalPayload;
  normalizedTelemetry?: Record<string, unknown>;
}) {
  const plan = input.plan,
    supplied = structuredClone({
      initialEvidence: input.initialEvidence,
      payload: input.payload,
      normalizedTelemetry: input.normalizedTelemetry,
    });
  if (
    [
      "captureSourceObservations",
      "captureSourceProofs",
      "captureSources",
      "privateCaptureStage",
    ].some((key) => Object.hasOwn(supplied.payload, key)) ||
    (supplied.payload.imageBase64s?.length ?? 0) > 0 ||
    (supplied.payload.audioBase64s?.length ?? 0) > 0 ||
    (supplied.payload.r2ObjectKeys?.length ?? 0) > 0 ||
    (supplied.payload.audioR2ObjectKeys?.length ?? 0) > 0 ||
    (supplied.payload.videoR2ObjectKeys?.length ?? 0) > 0
  ) return invalidHistory();
  if (supplied.payload.user_id !== plan.ownerID) return invalidHistory();
  const expectedPlan = initialCapturePlanValue(plan);
  const request = await initialRetentionRequest(supplied.initialEvidence);
  if (
    request.evidence_manifest.schema_version !== 9 ||
    request.scan_id !== plan.scanID || request.generation !== plan.generation
  ) return invalidHistory();
  const actualPlan = parseInitialEvidenceCapturePlan(plan.ownerID, {
    ...expectedPlan,
    items: request.evidence_manifest.items.map((item) =>
      item.kind === "audio"
        ? {
          kind: item.kind,
          source: item.source,
          prepared_media_id: item.prepared.media_id,
        }
        : item.kind === "video"
        ? {
          ...item,
          audio: item.audio === null ? null : {
            source: item.audio.source,
            prepared_media_id: item.audio.prepared.media_id,
          },
        }
        : item
    ),
  });
  if (
    JSON.stringify(initialCapturePlanValue(actualPlan)) !==
      JSON.stringify(expectedPlan)
  ) return invalidHistory();
  const binding = await initialCaptureAudioStageRequest(plan),
    mediaCounts = privateCaptureMediaCounts(request.evidence_manifest);
  const mediaObjectKeys = { image: [], audio: [], video: [] };
  // Reuse the established telemetry/goal sanitizers, but derive every evidence
  // association, field note and provider count from the complete V9 manifest.
  const legacy = await buildScanIngestionIntent({
    scanId: plan.scanID,
    payload: supplied.payload,
    normalizedTelemetry: supplied.normalizedTelemetry,
    mediaCounts,
    mediaObjectKeys,
  });
  const payload = {
    ...legacy.payload,
    telemetry: legacy.payload.telemetry as Record<string, unknown>,
    schemaVersion: PRIVATE_CAPTURE_INTENT_SCHEMA_VERSION,
    privateCaptureStage: {
      version: 1,
      generation: plan.generation,
      requestSHA256: binding.request_sha256,
    },
    initialEvidence: request,
    media: { r2ObjectKeys: [], audioR2ObjectKeys: [], videoR2ObjectKeys: [] },
    observationContexts: request.evidence_manifest.items.filter((item) =>
      item.kind === "description"
    ).map((item) => ({ freeText: item.text })),
    uploadSessionIds: [],
  };
  // Diagnostic checksum only. Begin stores its own authoritative JSONB digest
  // together with the immutable witness and returns that checksum to its caller.
  return {
    payloadSchemaVersion: PRIVATE_CAPTURE_INTENT_SCHEMA_VERSION,
    payload,
    payloadChecksum: await evidenceDigest(
      new TextEncoder().encode(JSON.stringify(payload)),
    ),
    mediaCounts,
    mediaObjectKeys,
    storageKeys: [] as string[],
    resumable: true,
    inlineMediaRedacted: false,
    redactedMediaCounts: { image_base64_count: 0, audio_base64_count: 0 },
  };
}
