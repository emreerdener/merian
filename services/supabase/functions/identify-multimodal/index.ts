import { Part, SafetyRating } from "@google/genai";
import { geminiUsageModalityBreakdown } from "../_shared/aiUsage.ts";
import {
  createClient,
  type SupabaseClient,
  type User,
} from "@supabase/supabase-js";

import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { requireClaimsAuth } from "../_shared/claimsAuth.ts";
import { corsHeaders } from "../_shared/http.ts";
import { authorizeServiceRoleRequest } from "../_shared/serviceRoleAuth.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { tierTelemetryProperties } from "../_shared/entitlement.ts";
import { reserveAIProviderCall } from "../_shared/aiQuota.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { deleteR2Object, getR2Config } from "../_shared/aws.ts";
import {
  coalesceTaxonomyValue,
  normalizeTaxonomyValue,
} from "../_shared/taxonomy.ts";

import {
  AudioMediaItemDTO,
  CachedSpeciesRow,
  ClientPayload,
  MerianIdentification,
  MultimodalPayload,
  VisualMediaItemDTO,
} from "../_shared/identify/types.ts";
import {
  hydratePayloadFromCachedSpecies,
  isNewToMerianDictionary,
} from "../_shared/identify/clientPayload.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertScan,
  mergeSpeciesCommonNames,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "../_shared/identify/db.ts";
import {
  beginScanIngestion,
  fetchIdentificationDictionaryHydration,
} from "../_shared/identify/latencyDb.ts";
import { normalizeProcessedMaterialSubject } from "../_shared/identify/subjectClassification.ts";
import { processWAV } from "./audio.ts";
import {
  resolveAudioBuffers,
  resolveImagePayloads,
  validateImageR2ObjectKeys,
} from "../_shared/identify/media.ts";
import {
  evaluateAndProcessPayload,
  promoteSafeMedia,
} from "../_shared/identify/moderation.ts";
import {
  MEDIA_BUDGETS,
  readRequestJsonWithinBudget,
} from "../_shared/mediaBudgets.ts";
import {
  claimScanIngestionJob,
  type ScanIngestionJobStatus,
  scanIngestionManifestChecksum,
  scanIngestionMediaObjectKeys,
  updateScanIngestionJob,
} from "../_shared/scanIngestionJobs.ts";
import {
  buildScanIngestionIntent,
  recordScanIngestionIntent,
} from "../_shared/scanIngestionIntents.ts";
import {
  fetchCaptureUploadSessionIdsForKeys,
  markStagedScanMediaAssetsDeleted,
  markStagedScanMediaAssetsFailed,
  markStagedScanMediaAssetsPromoted,
  refreshScanMediaAssets,
  refreshScanMediaAssetsBestEffort,
} from "../_shared/scanMediaAssets.ts";
import {
  buildContextText,
  normalizeCurrentMonth,
  sanitizeLifeStage,
  sanitizeObservationConfidence,
  sanitizeObservationEvidence,
  sanitizeReproductiveCondition,
  sanitizeSex,
} from "../_shared/identify/context.ts";

import { diagnosticTriggerForTier } from "../_shared/identify/thresholds.ts";
import {
  getMerianResponseSchema,
  getSystemInstruction as getVisionSystemInstruction,
} from "../_shared/identify/schema.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizePetIdentification,
  sanitizeScientificName,
} from "../identify/sanitize.ts";

const BIOACOUSTIC_SYSTEM_INSTRUCTION = `# Role
You are a world-class bioacoustic field biologist with expertise in identifying species from their acoustic signatures across all taxa: birds, insects, frogs, mammals, and other wildlife.

# Task
Listen to the provided audio recording and identify the primary biological sound source, if any.

# Response Rules
- is_biological_subject: true only when a genuine biological vocalization is detected. false for wind, rain, mechanical noise, silence, or human speech without wildlife.
- scientific_name: formal binomial nomenclature (Genus species) for the primary identified species. Omit entirely if is_biological_subject is false.
- confidence_score: 0.0–1.0. Use below 0.70 when the recording is ambiguous, noisy, or the call is partially obscured.
- ai_reasoning: concise acoustic diagnosis citing observable call characteristics (frequency, tempo, pattern, note duration, harmonic structure). Be specific.
- ecology_type: "wild" for natural habitat, "urban" for urban/suburban, "domesticated" for pets or livestock.
- sex: use female, male, mixed, hermaphrodite, cannot_determine, or not_applicable. Only report female/male/mixed when the recording contains explicit species-specific acoustic evidence that distinguishes sex; otherwise use cannot_determine. Never infer or report human sex/gender.
- sex_confidence: 0.0–1.0 confidence in the sex annotation from direct acoustic evidence only. Omit when sex is cannot_determine or not_applicable.
- sex_evidence: short acoustic cue supporting sex, such as sex-specific song, call type, or duet role. Omit when unsupported.
- Use authoritative nomenclature (Clements Checklist v2024 for birds, GBIF Backbone Taxonomy for all other taxa).
- Never fabricate scientific names.`;

const DESCRIBE_SYSTEM_INSTRUCTION = `# Role
You are a taxonomic analyst interpreting user text descriptions to identify biological subjects.

# Task
Read the user's description and identify the biological subject they are describing.

# Non-Biological Descriptions
Manufactured or processed objects are not biological subjects even when made from biological material. Wool rugs/kilims/carpets, leather goods, wooden furniture, paper/cardboard, cotton or linen fabric, prepared food, toys, artwork, ornaments, and printed/painted/sculpted species depictions must return is_biological_subject=false and must not be identified as their source organism or carry a source-organism scientific_name.

# Sex
Report sex only when the user's description contains diagnostic evidence for the primary subject. Never infer sex from species name, population tendency, or stereotypes. Never infer or report human sex/gender; use not_applicable for human subjects. Use cannot_determine when evidence is absent or non-diagnostic.`;

const MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION = `# Role
You are an expert encyclopedic field-guide biologist and taxonomist with specialized expertise in cross-modal taxonomy.

# Core Directives
- **Holistic Evaluation:** Evaluate all visual evidence and audio evidence sequentially before formulating a combined taxonomic confidence score. Visual evidence may include still photos or sampled frames from a short user-recorded video.
- **Modality Synthesis:** Weigh BOTH visual and acoustic evidence. Prioritize the bio-acoustic trace unless it clearly contradicts the vision context or the vision context is overwhelmingly diagnostic.
- **Reporting:** Your \`ai_reasoning\` MUST encompass BOTH modalities, explaining how they corroborate or contradict each other.
- **Video Language:** When the scan includes video, refer to the evidence as video, a video scan, or sampled frames/audio from the video. Do not describe video scans as images, photos, or a set of provided images in user-facing reasoning.
- **Processed Materials Are Not Biological Subjects:** Manufactured or processed objects are \`is_biological_subject=false\` even when made from biological material. This includes wool rugs/kilims/carpets, leather goods, wooden furniture, paper/cardboard, cotton or linen fabric, prepared food, toys, artwork, ornaments, and printed/painted/sculpted species depictions. Do NOT classify a rug as sheep, leather as cattle, wood furniture as a tree, paper as a plant, or a species drawing/toy as the depicted organism; do not include a source-organism scientific_name for these results.
- **Sex:** Report sex only when visual, described, or acoustic evidence is diagnostic for the primary subject. Never infer sex from species name, population tendency, or stereotypes. Never infer or report human sex/gender; use not_applicable for human subjects. Use cannot_determine when evidence is absent or non-diagnostic.`;

const telemetryCount = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.trunc(value);
};

type VisualMediaDescriptor = {
  kind: "image" | "video_frame";
  sourceIndex?: number;
  clipIndex?: number;
  frameIndex?: number;
  focusRegion?: NormalizedFocusRegion;
};

type NormalizedFocusRegion = {
  x: number;
  y: number;
  width: number;
  height: number;
  source: "vision_objectness";
};

type AudioMediaDescriptor = {
  kind: "audio" | "video_audio";
  sourceIndex?: number;
  clipIndex?: number;
};

type StoredMediaReferenceDTO = {
  storage: "remoteURL";
  path: string;
};

type SerializedMediaItemDTO =
  | { image: { _0: StoredMediaReferenceDTO } }
  | { audio: { _0: StoredMediaReferenceDTO } }
  | {
    video: {
      _0: {
        video: StoredMediaReferenceDTO;
        thumbnail?: StoredMediaReferenceDTO;
      };
    };
  };

const optionalIndex = (value: unknown): number | undefined => {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return undefined;
  }
  return Math.trunc(value);
};

function normalizeFocusRegion(
  rawRegion: unknown,
): NormalizedFocusRegion | undefined {
  if (!rawRegion || typeof rawRegion !== "object" || Array.isArray(rawRegion)) {
    return undefined;
  }

  const region = rawRegion as Record<string, unknown>;
  const { x, y, width, height, source } = region;
  if (
    typeof x !== "number" || !Number.isFinite(x) ||
    typeof y !== "number" || !Number.isFinite(y) ||
    typeof width !== "number" || !Number.isFinite(width) ||
    typeof height !== "number" || !Number.isFinite(height) ||
    source !== "vision_objectness" ||
    x < 0 || y < 0 || width <= 0 || height <= 0 ||
    x > 1 || y > 1 || x + width > 1 || y + height > 1
  ) {
    return undefined;
  }

  return { x, y, width, height, source };
}

function normalizeVisualMediaItems(
  rawItems: unknown,
  resolvedImageCount: number,
): VisualMediaDescriptor[] {
  if (!Array.isArray(rawItems) || rawItems.length !== resolvedImageCount) {
    return [];
  }

  const descriptors: VisualMediaDescriptor[] = [];
  for (const rawItem of rawItems) {
    if (!rawItem || typeof rawItem !== "object") {
      return [];
    }

    const item = rawItem as VisualMediaItemDTO;
    if (item.kind !== "image" && item.kind !== "video_frame") {
      return [];
    }

    descriptors.push({
      kind: item.kind,
      sourceIndex: optionalIndex(item.sourceIndex ?? item.source_index),
      clipIndex: optionalIndex(item.clipIndex ?? item.clip_index),
      frameIndex: optionalIndex(item.frameIndex ?? item.frame_index),
      focusRegion: item.kind === "image"
        ? normalizeFocusRegion(item.focusRegion ?? item.focus_region)
        : undefined,
    });
  }

  return descriptors;
}

function normalizeAudioMediaItems(
  rawItems: unknown,
  resolvedAudioCount: number,
): AudioMediaDescriptor[] {
  if (!Array.isArray(rawItems) || rawItems.length !== resolvedAudioCount) {
    return [];
  }

  const descriptors: AudioMediaDescriptor[] = [];
  for (const rawItem of rawItems) {
    if (!rawItem || typeof rawItem !== "object") {
      return [];
    }

    const item = rawItem as AudioMediaItemDTO;
    if (item.kind !== "audio" && item.kind !== "video_audio") {
      return [];
    }

    descriptors.push({
      kind: item.kind,
      sourceIndex: optionalIndex(item.sourceIndex ?? item.source_index),
      clipIndex: optionalIndex(item.clipIndex ?? item.clip_index),
    });
  }

  return descriptors;
}

function resolveVisualMediaTelemetry(
  resolvedImageCount: number,
  videoFrameCount: unknown,
  videoClipCount: number,
  visualMediaItems: VisualMediaDescriptor[] = [],
) {
  if (visualMediaItems.length === resolvedImageCount) {
    const videoInferenceFrameCount = visualMediaItems.filter((item) =>
      item.kind === "video_frame"
    ).length;
    const imageCount = Math.max(
      resolvedImageCount - videoInferenceFrameCount,
      0,
    );
    const hasVideo = videoClipCount > 0 || videoInferenceFrameCount > 0;
    const hasImage = imageCount > 0;
    const mediaType = hasVideo && hasImage
      ? "image_video"
      : hasVideo
      ? "video"
      : hasImage
      ? "image"
      : "none";

    return {
      mediaType,
      hasImage,
      hasVideo,
      imageCount,
      videoClipCount,
      declaredVideoFrameCount: videoInferenceFrameCount,
      videoInferenceFrameCount,
    };
  }

  const declaredVideoFrameCount = telemetryCount(videoFrameCount);
  const hasVideo = videoClipCount > 0 || declaredVideoFrameCount > 0;
  const videoInferenceFrameCount = hasVideo
    ? Math.min(
      resolvedImageCount,
      declaredVideoFrameCount > 0
        ? declaredVideoFrameCount
        : resolvedImageCount,
    )
    : 0;
  const imageCount = Math.max(resolvedImageCount - videoInferenceFrameCount, 0);
  const hasImage = imageCount > 0;
  const mediaType = hasVideo && hasImage
    ? "image_video"
    : hasVideo
    ? "video"
    : hasImage
    ? "image"
    : "none";

  return {
    mediaType,
    hasImage,
    hasVideo,
    imageCount,
    videoClipCount,
    declaredVideoFrameCount,
    videoInferenceFrameCount,
  };
}

function buildVisualMediaPrompt(
  visualMediaItems: VisualMediaDescriptor[],
  hasVideo: boolean,
  resolvedImageCount: number,
  hasVideoAudio = false,
): string | null {
  if (
    visualMediaItems.length === resolvedImageCount &&
    visualMediaItems.length > 0
  ) {
    const includesVideo = visualMediaItems.some((item) =>
      item.kind === "video_frame"
    );
    const lines = visualMediaItems.map((item, index) => {
      const inputNumber = index + 1;
      if (item.kind === "video_frame") {
        const clipNumber = (item.clipIndex ?? 0) + 1;
        const frameNumber = (item.frameIndex ?? index) + 1;
        return `- Visual input ${inputNumber}: sampled video frame ${frameNumber} from video clip ${clipNumber}.`;
      }

      const sourceNumber = (item.sourceIndex ?? index) + 1;
      const photoLabel =
        `- Visual input ${inputNumber}: still photo ${sourceNumber}.`;
      if (!item.focusRegion) return photoLabel;

      const { x, y, width, height } = item.focusRegion;
      return `${photoLabel} The likely primary subject is inside top-left-normalized bounds x=${
        x.toFixed(4)
      }, y=${y.toFixed(4)}, width=${width.toFixed(4)}, height=${
        height.toFixed(4)
      } in this same photo. Prioritize that region while treating everything outside it as environmental context.`;
    });

    const promptLines = includesVideo
      ? [
        "This scan includes a short user-recorded video. The visual evidence comes from ordered sampled frames from that video, with any listed still photos treated as separate evidence from the same scan.",
      ]
      : [
        "The following visual inputs are ordered still photos from the same scan:",
      ];

    promptLines.push(
      ...lines,
    );

    if (includesVideo) {
      promptLines.push(
        hasVideoAudio
          ? "Analyze the sampled visual frames and accompanying audio as evidence from that video."
          : "Analyze the sampled visual frames as evidence from that video.",
        "When writing user-facing reasoning for this video scan, do not describe the video-derived evidence as images, photos, or an image set.",
      );
    }

    return promptLines.join("\n");
  }

  if (hasVideo && resolvedImageCount > 0) {
    return [
      "This scan includes a short user-recorded video. The visual evidence comes from ordered sampled frames from that video.",
      hasVideoAudio
        ? "Analyze the sampled visual frames and accompanying audio as evidence from that video."
        : "Analyze the sampled visual frames as evidence from that video.",
      "When writing user-facing reasoning for this video scan, do not describe the video-derived evidence as images, photos, or an image set.",
    ].join("\n");
  }

  return null;
}

function remoteMediaReference(url: string): StoredMediaReferenceDTO {
  return { storage: "remoteURL", path: url };
}

function publicUrlsByStorageKey(
  storageKeys: string[],
  publicUrls: string[],
): Map<string, string> {
  const urlsByStorageKey = new Map<string, string>();
  const count = Math.min(storageKeys.length, publicUrls.length);
  for (let index = 0; index < count; index++) {
    const storageKey = storageKeys[index]?.trim();
    const publicUrl = publicUrls[index]?.trim();
    if (storageKey && publicUrl) {
      urlsByStorageKey.set(storageKey, publicUrl);
    }
  }
  return urlsByStorageKey;
}

function buildCapturedMediaManifest(
  imageStorageUrls: string[],
  videoStorageUrls: string[],
  audioStorageUrls: string[],
  visualMediaItems: VisualMediaDescriptor[],
  audioMediaItems: AudioMediaDescriptor[],
): SerializedMediaItemDTO[] | null {
  const sanitizedImageUrls = imageStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
  const sanitizedVideoUrls = videoStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
  const sanitizedAudioUrls = audioStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);

  if (
    sanitizedImageUrls.length === 0 && sanitizedVideoUrls.length === 0 &&
    sanitizedAudioUrls.length === 0
  ) {
    return null;
  }

  const items: SerializedMediaItemDTO[] = [];
  const emittedVideoClipIndexes = new Set<number>();

  if (visualMediaItems.length === sanitizedImageUrls.length) {
    for (const [inputIndex, descriptor] of visualMediaItems.entries()) {
      const imageUrl = sanitizedImageUrls[inputIndex];
      if (!imageUrl) continue;

      if (descriptor.kind === "image") {
        items.push({ image: { _0: remoteMediaReference(imageUrl) } });
        continue;
      }

      const clipIndex = descriptor.clipIndex ?? 0;
      if (emittedVideoClipIndexes.has(clipIndex)) continue;

      const videoUrl = sanitizedVideoUrls[clipIndex];
      if (!videoUrl) continue;

      emittedVideoClipIndexes.add(clipIndex);
      items.push({
        video: {
          _0: {
            video: remoteMediaReference(videoUrl),
            thumbnail: remoteMediaReference(imageUrl),
          },
        },
      });
    }
  }

  const standaloneAudioUrls =
    audioMediaItems.length === sanitizedAudioUrls.length
      ? audioMediaItems.flatMap((descriptor, index) =>
        descriptor.kind === "audio" && sanitizedAudioUrls[index]
          ? [sanitizedAudioUrls[index]]
          : []
      )
      : sanitizedVideoUrls.length === 0
      ? sanitizedAudioUrls
      : [];

  for (const audioUrl of standaloneAudioUrls) {
    items.push({ audio: { _0: remoteMediaReference(audioUrl) } });
  }

  if (items.length > 0) {
    return items;
  }

  if (sanitizedVideoUrls.length > 0) {
    return sanitizedVideoUrls.map((videoUrl, index) => {
      const thumbnailUrl = sanitizedImageUrls[index] ?? sanitizedImageUrls[0];
      const video: SerializedMediaItemDTO = {
        video: {
          _0: {
            video: remoteMediaReference(videoUrl),
          },
        },
      };

      if (thumbnailUrl) {
        video.video._0.thumbnail = remoteMediaReference(thumbnailUrl);
      }

      return video;
    });
  }

  const imageItems: SerializedMediaItemDTO[] = sanitizedImageUrls.map((
    imageUrl,
  ) => ({
    image: { _0: remoteMediaReference(imageUrl) },
  }));
  return [
    ...imageItems,
    ...standaloneAudioUrls.map((audioUrl): SerializedMediaItemDTO => ({
      audio: { _0: remoteMediaReference(audioUrl) },
    })),
  ];
}

function capturedMediaVideoCount(
  capturedMedia: SerializedMediaItemDTO[] | null,
): number {
  return (capturedMedia ?? []).filter((item) => "video" in item).length;
}

function retryAfterIso(minutes = 5): string {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

const INTERNAL_REPLAY_HEADER = "X-Merian-Internal-Replay";
const INTERNAL_REPLAY_USER_HEADER = "X-Merian-Replay-User-Id";

interface ServerTimingMetric {
  name: string;
  durationMs: number;
}

function serverTimingValue(metrics: ServerTimingMetric[]): string {
  return metrics
    .filter((metric) =>
      Number.isFinite(metric.durationMs) && metric.durationMs >= 0
    )
    .map((metric) => `${metric.name};dur=${metric.durationMs.toFixed(1)}`)
    .join(", ");
}

export async function handleIdentifyMultimodalRequest(
  req: Request,
  user: User,
  supabaseAdmin: SupabaseClient,
  authDurationMs = 0,
): Promise<Response> {
  const fnStart = Date.now();
  const bodyReadStart = performance.now();
  const bodyReadResult = await readRequestJsonWithinBudget<
    Record<string, unknown>
  >(
    req,
    MEDIA_BUDGETS.maxMultimodalJsonBodyBytes,
  );
  const bodyReadMs = performance.now() - bodyReadStart;
  if (bodyReadResult.error || !bodyReadResult.value) {
    return jsonResponse(
      { error: bodyReadResult.error?.message ?? "Invalid JSON body" },
      bodyReadResult.error?.status ?? 400,
    );
  }

  const rawBody = bodyReadResult.value;

  const paramError = requireParams(rawBody, ["user_id"]);
  if (paramError) return paramError;

  const payload = rawBody as unknown as MultimodalPayload; // Trigger TS Language Server refresh
  const {
    client_scan_id,
    timestamp,
    imageBase64s = [],
    audioBase64s = [],
    audioR2ObjectKeys = [],
    videoR2ObjectKeys = [],
    videoFrameCount = 0,
    visualMediaItems,
    visual_media_items,
    audioMediaItems,
    audio_media_items,
    observation_contexts = [],
    r2ObjectKeys = [],
    mimeType = "image/webp",
  } = payload;

  // The active Swift client sends camelCase telemetry while older queued payloads and
  // some server-side tooling still use snake_case. Accept both forms so the live path
  // remains backward-compatible during migrations and offline queue replays.
  const gpsLatitude = payload.gpsLatitude ?? payload.gps_latitude;
  const gpsLongitude = payload.gpsLongitude ?? payload.gps_longitude;
  const gpsElevation = payload.gpsElevation ?? payload.gps_elevation;
  const semanticLocation = payload.semanticLocation ??
    payload.semantic_location;
  const publicExploreLocationLabel = payload.publicLocationLabel ??
    payload.public_location_label;
  const scanGeoprivacy = payload.geoprivacy;
  const weatherCondition = payload.weatherCondition ??
    payload.weather_condition;
  const weatherTemperatureF = payload.weatherTemperatureF ??
    payload.weather_temperature_f;
  const deviceLocale = payload.deviceLocale ?? payload.device_locale;
  const deviceTimeZone = payload.deviceTimeZone ?? payload.device_time_zone;
  const deviceRegion = payload.deviceRegion ?? payload.device_region;
  const currentMonth = normalizeCurrentMonth(
    payload.currentMonth ?? payload.current_month,
  );
  const timeOfDay = payload.timeOfDay ?? payload.time_of_day;
  const depthScaleText = payload.depthScaleText ?? payload.depth_scale_text;
  const zoomFactor = payload.zoomFactor;
  const estimatedSizeCm = payload.estimatedSizeCm ??
    payload.estimated_size_cm;

  const generatedScanId =
    typeof client_scan_id === "string" && client_scan_id.length > 0
      ? client_scan_id
      : crypto.randomUUID();

  const updateIngestionJobBestEffort = async (
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
          scanId: generatedScanId,
          userId: user.id,
          status,
          stage,
          lastError: options.lastError ?? null,
          retryAfter: options.retryAfter ?? null,
          leaseSeconds: options.leaseSeconds,
        },
        supabaseAdmin,
      );
    } catch (error) {
      logStructuredError("multimodal/scan_ingestion_job_update_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        status,
        stage,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };

  const safeGpsLat: number | null =
    gpsLatitude != null && Number.isFinite(gpsLatitude) &&
      gpsLatitude >= -90 && gpsLatitude <= 90
      ? gpsLatitude
      : null;
  const safeGpsLon: number | null =
    gpsLongitude != null && Number.isFinite(gpsLongitude) &&
      gpsLongitude >= -180 && gpsLongitude <= 180
      ? gpsLongitude
      : null;

  // 1. Image Resolution (R2 Fetching + IDOR Check)
  const keyValidationError = validateImageR2ObjectKeys(
    r2ObjectKeys,
    user.id,
    {
      enforceOwnership: true,
      idorEvent: "multimodal/image_idor_attempt",
    },
  );
  if (keyValidationError) return keyValidationError;

  const videoKeyValidationError = validateImageR2ObjectKeys(
    videoR2ObjectKeys,
    user.id,
    {
      enforceOwnership: true,
      idorEvent: "multimodal/video_idor_attempt",
      wrongUserMessage:
        "Forbidden: videoR2ObjectKey does not belong to the requesting user.",
    },
  );
  if (videoKeyValidationError) return videoKeyValidationError;

  const { base64Payloads, errorResponse } = await resolveImagePayloads(
    r2ObjectKeys,
    imageBase64s,
    fnStart,
  );

  if (errorResponse) return errorResponse;

  const resolvedImageBase64s = base64Payloads || [];
  const normalizedVisualMediaItems = normalizeVisualMediaItems(
    visualMediaItems ?? visual_media_items,
    resolvedImageBase64s.length,
  );
  const mediaTelemetry = resolveVisualMediaTelemetry(
    resolvedImageBase64s.length,
    videoFrameCount,
    videoR2ObjectKeys.length,
    normalizedVisualMediaItems,
  );

  // 2. WAV Preprocessing Loop
  const processedAudios: string[] = [];
  if (audioBase64s.length > 0 || audioR2ObjectKeys.length > 0) {
    const { audioBuffers, errorResponse: audioErrorResponse } =
      await resolveAudioBuffers({
        userId: user.id,
        audioR2ObjectKeys,
        audioBase64s,
        idorEvent: "multimodal/audio_idor_attempt",
        r2FetchFailedEvent: "multimodal/audio_r2_fetch_failed",
      });
    if (audioErrorResponse) return audioErrorResponse;
    const hasVisualEvidence = resolvedImageBase64s.length > 0;
    for (const audioBuffer of audioBuffers) {
      try {
        processedAudios.push(await processWAV(audioBuffer));
      } catch (wavErr) {
        logStructuredError("multimodal/wav_parse_failed", {
          user_id: user.id,
          error: String(wavErr),
          skipped: hasVisualEvidence,
        });
        if (!hasVisualEvidence) {
          return jsonResponse({ error: "Invalid audio file format." }, 400);
        }
      }
    }
  }
  const normalizedAudioMediaItems = normalizeAudioMediaItems(
    audioMediaItems ?? audio_media_items,
    processedAudios.length,
  );
  const hasVideoAudio =
    normalizedAudioMediaItems.some((item) => item.kind === "video_audio") ||
    (mediaTelemetry.hasVideo && processedAudios.length > 0);

  // 2. Dispatch Rule
  const tierStart = performance.now();
  const quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
    userId: user.id,
    operation: "scan_identification",
    requestId: generatedScanId,
  });
  const tierResolution = quotaLease.reservation.tier;
  const tierMs = performance.now() - tierStart;
  const userTier = tierResolution.effective_tier;
  const inferenceTier = userTier === "pro" ? "pro" : "flash";
  const targetModel = quotaLease.reservation.model;
  const diagnosticTrigger = diagnosticTriggerForTier(inferenceTier);

  let instructionToUse = "";
  if (resolvedImageBase64s.length > 0 && processedAudios.length > 0) {
    instructionToUse = MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION;
  } else if (resolvedImageBase64s.length > 0) {
    instructionToUse = getVisionSystemInstruction(diagnosticTrigger);
  } else if (processedAudios.length > 0) {
    instructionToUse = BIOACOUSTIC_SYSTEM_INSTRUCTION;
  } else {
    instructionToUse = DESCRIBE_SYSTEM_INSTRUCTION;
  }

  // 3. Modality Assembly
  const partsArray: Part[] = [];
  let hasObservationContextText = false;
  if (observation_contexts.length > 0) {
    const mergedContexts = observation_contexts
      .map((c) =>
        typeof c.freeText === "string" && c.freeText.trim().length > 0
          ? c.freeText.trim()
          : (typeof c.free_text === "string" && c.free_text.trim().length > 0
            ? c.free_text.trim()
            : null)
      )
      .filter((text): text is string => text != null);
    if (mergedContexts.length > 0) {
      hasObservationContextText = true;
      partsArray.push({
        text: `Additional observation context from user:\n${
          mergedContexts.join(
            "\n",
          )
        }`,
      });
    }
  }

  const visualMediaPrompt = buildVisualMediaPrompt(
    normalizedVisualMediaItems,
    mediaTelemetry.hasVideo,
    resolvedImageBase64s.length,
    hasVideoAudio,
  );
  if (visualMediaPrompt) {
    partsArray.push({ text: visualMediaPrompt });
  }

  for (const b64 of resolvedImageBase64s) {
    partsArray.push({ inlineData: { mimeType, data: b64 } });
  }

  for (const audio of processedAudios) {
    partsArray.push({ inlineData: { mimeType: "audio/wav", data: audio } });
  }

  partsArray.push({
    text: buildContextText({
      safeGpsLat,
      safeGpsLon,
      gpsElevation,
      depthScaleText,
      zoomFactor,
      estimatedSizeCm,
      semanticLocation,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      deviceTimeZone,
      deviceRegion,
      currentMonth,
      timeOfDay,
    }),
  });

  if (partsArray.length === 1 && !hasObservationContextText) {
    await quotaLease.refund();
    return jsonResponse({
      error: "At least one media element or description is required",
    }, 400);
  }

  const mediaCounts = {
    image_count: mediaTelemetry.imageCount,
    audio_count: processedAudios.length,
    video_count: mediaTelemetry.videoClipCount,
    required_video_count: videoR2ObjectKeys.length,
    video_frame_count: mediaTelemetry.declaredVideoFrameCount,
    video_inference_frame_count: mediaTelemetry.videoInferenceFrameCount,
    has_description: hasObservationContextText,
  };
  const mediaObjectKeys = scanIngestionMediaObjectKeys({
    imageKeys: r2ObjectKeys,
    audioKeys: audioR2ObjectKeys,
    videoKeys: videoR2ObjectKeys,
  });

  const storageKeys = [
    ...mediaObjectKeys.image,
    ...mediaObjectKeys.audio,
    ...mediaObjectKeys.video,
  ];
  let uploadSessionIds: string[] = [];
  let manifestChecksum = await scanIngestionManifestChecksum({
    mediaCounts,
    mediaObjectKeys,
    uploadSessionIds,
  });
  let ingestionIntent = await buildScanIngestionIntent({
    scanId: generatedScanId,
    payload,
    mediaCounts,
    mediaObjectKeys,
    uploadSessionIds,
    manifestChecksum,
    visualMediaItems: normalizedVisualMediaItems,
    audioMediaItems: normalizedAudioMediaItems,
    normalizedTelemetry: {
      timestamp,
      gpsLatitude: safeGpsLat,
      gpsLongitude: safeGpsLon,
      gpsElevation,
      semanticLocation,
      publicLocationLabel: publicExploreLocationLabel,
      geoprivacy: scanGeoprivacy,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      deviceTimeZone,
      deviceRegion,
      currentMonth,
      timeOfDay,
      depthScaleText,
      zoomFactor,
      estimatedSizeCm,
    },
  });

  const preGeminiDbStart = performance.now();
  try {
    const atomicIngestion = await beginScanIngestion(
      {
        scanId: generatedScanId,
        userId: user.id,
        endpoint: "identify-multimodal",
        requestPayload: ingestionIntent.payload,
        mediaCounts,
        mediaObjectKeys,
        storageKeys,
        manifestChecksum,
        payloadChecksum: ingestionIntent.payloadChecksum,
        resumable: ingestionIntent.resumable,
        inlineMediaRedacted: ingestionIntent.inlineMediaRedacted,
        redactedMediaCounts: ingestionIntent.redactedMediaCounts,
        leaseSeconds: 300,
      },
      supabaseAdmin,
    );
    uploadSessionIds = atomicIngestion.uploadSessionIds;
    manifestChecksum = atomicIngestion.manifestChecksum ?? manifestChecksum;
  } catch (error) {
    // Safe rollout fallback while the atomic RPC migration propagates.
    logStructuredError("multimodal/atomic_ingestion_setup_fallback", {
      user_id: user.id,
      scan_id: generatedScanId,
      error: error instanceof Error ? error.message : String(error),
    });

    try {
      uploadSessionIds = await fetchCaptureUploadSessionIdsForKeys(
        { userId: user.id, clientScanId: generatedScanId, storageKeys },
        supabaseAdmin,
      );
      manifestChecksum = await scanIngestionManifestChecksum({
        mediaCounts,
        mediaObjectKeys,
        uploadSessionIds,
      });
      ingestionIntent = await buildScanIngestionIntent({
        scanId: generatedScanId,
        payload,
        mediaCounts,
        mediaObjectKeys,
        uploadSessionIds,
        manifestChecksum,
        visualMediaItems: normalizedVisualMediaItems,
        audioMediaItems: normalizedAudioMediaItems,
        normalizedTelemetry: {
          timestamp,
          gpsLatitude: safeGpsLat,
          gpsLongitude: safeGpsLon,
          gpsElevation,
          semanticLocation,
          publicLocationLabel: publicExploreLocationLabel,
          geoprivacy: scanGeoprivacy,
          weatherCondition,
          weatherTemperatureF,
          deviceLocale,
          deviceTimeZone,
          deviceRegion,
          currentMonth,
          timeOfDay,
          depthScaleText,
          zoomFactor,
          estimatedSizeCm,
        },
      });
      await claimScanIngestionJob(
        {
          scanId: generatedScanId,
          userId: user.id,
          endpoint: "identify-multimodal",
          mediaCounts,
          mediaObjectKeys,
          uploadSessionIds,
          manifestChecksum,
          leaseSeconds: 300,
        },
        supabaseAdmin,
      );
      await recordScanIngestionIntent(
        {
          scanId: generatedScanId,
          userId: user.id,
          endpoint: "identify-multimodal",
          requestPayload: ingestionIntent.payload,
          mediaCounts,
          mediaObjectKeys,
          uploadSessionIds,
          manifestChecksum,
          payloadChecksum: ingestionIntent.payloadChecksum,
          resumable: ingestionIntent.resumable,
          inlineMediaRedacted: ingestionIntent.inlineMediaRedacted,
          redactedMediaCounts: ingestionIntent.redactedMediaCounts,
        },
        supabaseAdmin,
      );
      await updateIngestionJobBestEffort(
        "processing",
        "ai_inference_started",
        { leaseSeconds: 300 },
      );
    } catch (fallbackError) {
      logStructuredError("multimodal/scan_ingestion_setup_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: fallbackError instanceof Error
          ? fallbackError.message
          : String(fallbackError),
      });
    }
  }
  const preGeminiDbMs = performance.now() - preGeminiDbStart;

  // 4. Invocation
  const geminiStart = Date.now();
  let responseText = "";
  let finishReason: string | undefined;
  let safetyRatings: SafetyRating[] | undefined;

  let llmPromptTokens: number | null = null;
  let llmCandidateTokens: number | null = null;
  let llmThinkingTokens: number | null = null;
  let llmTotalTokens: number | null = null;
  let llmUsageMetadata: Record<string, unknown> = {};
  let geminiLatencyMs = 0;

  try {
    await quotaLease.commit();
    const result = await _genAI.models.generateContent({
      model: targetModel,
      contents: [{ role: "user", parts: partsArray }],
      config: {
        systemInstruction: instructionToUse,
        temperature: 0.1,
        seed: 42,
        maxOutputTokens: 8192,
        thinkingConfig: userTier === "pro"
          ? { thinkingBudget: 5000 }
          : undefined,
        responseMimeType: "application/json",
        responseSchema: getMerianResponseSchema(diagnosticTrigger),
      },
    });
    geminiLatencyMs = Date.now() - geminiStart;

    finishReason = result.candidates?.[0]?.finishReason;
    safetyRatings = result.candidates?.[0]?.safetyRatings;
    responseText = result.text ?? "";

    const usage = result.usageMetadata;
    if (usage) {
      llmUsageMetadata = geminiUsageModalityBreakdown(usage);
      llmPromptTokens = usage.promptTokenCount ?? null;
      llmCandidateTokens = usage.candidatesTokenCount ?? null;
      llmThinkingTokens = usage.thoughtsTokenCount ?? null;
      llmTotalTokens = usage.totalTokenCount ?? null;
    }
  } catch (genErr) {
    geminiLatencyMs = Date.now() - geminiStart;
    logStructuredError("multimodal/gemini_failed", {
      user_id: user.id,
      error: String(genErr),
    });
    await updateIngestionJobBestEffort(
      "failed_retryable",
      "ai_inference_failed",
      {
        lastError: genErr instanceof Error ? genErr.message : String(genErr),
        retryAfter: retryAfterIso(),
      },
    );
    return jsonResponse(
      { error: "AI processing error. Please try again." },
      503,
    );
  }
  const geminiCompletedAt = Date.now();

  if (
    finishReason && finishReason !== "STOP" &&
    finishReason !== "FINISH_REASON_UNSPECIFIED"
  ) {
    const isPermanent = finishReason === "SAFETY" ||
      finishReason === "PROHIBITED_CONTENT";
    logStructuredError("multimodal/non_stop_finish", {
      user_id: user.id,
      finish_reason: finishReason,
    });
    await updateIngestionJobBestEffort(
      isPermanent ? "failed_terminal" : "failed_retryable",
      "ai_inference_non_stop_finish",
      {
        lastError: `AI finish reason: ${finishReason}`,
        retryAfter: isPermanent ? null : retryAfterIso(),
      },
    );
    return jsonResponse(
      { error: `AI processing error (${finishReason}).` },
      isPermanent ? 400 : 503,
    );
  }

  let parsedData: MerianIdentification;
  try {
    parsedData = extractJson<MerianIdentification>(responseText);
  } catch {
    await updateIngestionJobBestEffort(
      "failed_retryable",
      "ai_response_malformed",
      {
        lastError: "Malformed AI response.",
        retryAfter: retryAfterIso(),
      },
    );
    return jsonResponse(
      { error: "Processing Error: Malformed AI response." },
      422,
    );
  }

  if (parsedData.scientific_name) {
    parsedData.scientific_name = sanitizeScientificName(
      parsedData.scientific_name,
    );
    parsedData.scientific_name = canonicalizeDomesticPetScientificName(
      parsedData.scientific_name,
      parsedData.pet_identification,
      parsedData.common_name,
    );
  }
  parsedData.pet_identification = sanitizePetIdentification(
    parsedData.pet_identification,
    parsedData.scientific_name,
  );
  if (Array.isArray(parsedData.candidates)) {
    parsedData.candidates = parsedData.candidates
      .map((candidate) => ({
        ...candidate,
        scientific_name: sanitizeScientificName(candidate.scientific_name),
      }))
      .slice(0, 5);
  }
  if (Array.isArray(parsedData.extracted_visual_traits)) {
    parsedData.extracted_visual_traits = parsedData.extracted_visual_traits
      .slice(0, 10);
  }
  if (Array.isArray(parsedData.ecological_interactions)) {
    parsedData.ecological_interactions = parsedData.ecological_interactions
      .slice(0, 10);
  }
  if (
    typeof parsedData.ai_reasoning === "string" &&
    parsedData.ai_reasoning.length > 2000
  ) {
    parsedData.ai_reasoning = parsedData.ai_reasoning.slice(0, 2000);
  }
  if (parsedData.individual_count != null) {
    parsedData.individual_count =
      Number.isFinite(parsedData.individual_count) &&
        parsedData.individual_count > 0
        ? Math.min(Math.round(parsedData.individual_count), 99999)
        : undefined;
  }
  const sanitizedLifeStage = sanitizeLifeStage(parsedData.life_stage);
  if (
    parsedData.life_stage != null &&
    sanitizedLifeStage != parsedData.life_stage
  ) {
    logStructuredError("multimodal/unknown_life_stage", {
      user_id: user.id,
      value: parsedData.life_stage,
    });
  }
  parsedData.life_stage = sanitizedLifeStage;

  const sanitizedReproductiveCondition = sanitizeReproductiveCondition(
    parsedData.reproductive_condition,
  );
  if (
    parsedData.reproductive_condition != null &&
    sanitizedReproductiveCondition != parsedData.reproductive_condition
  ) {
    logStructuredError("multimodal/unknown_reproductive_condition", {
      user_id: user.id,
      value: parsedData.reproductive_condition,
    });
  }
  parsedData.reproductive_condition = sanitizedReproductiveCondition;

  const sanitizedSex = sanitizeSex(parsedData.sex);
  if (parsedData.sex != null && sanitizedSex != parsedData.sex) {
    logStructuredError("multimodal/unknown_sex", {
      user_id: user.id,
      value: parsedData.sex,
    });
  }
  parsedData.sex = sanitizedSex;
  parsedData.sex_confidence = sanitizeObservationConfidence(
    parsedData.sex_confidence,
  );
  parsedData.sex_evidence = sanitizeObservationEvidence(
    parsedData.sex_evidence,
  );
  parsedData.invasive_status_region = sanitizeObservationEvidence(
    parsedData.invasive_status_region,
    160,
  );
  parsedData.invasive_rationale = sanitizeObservationEvidence(
    parsedData.invasive_rationale,
    500,
  );
  parsedData.invasive_confidence = sanitizeObservationConfidence(
    parsedData.invasive_confidence,
  );
  const processedMaterialNormalization = normalizeProcessedMaterialSubject(
    parsedData,
  );
  if (processedMaterialNormalization.demoted) {
    logStructuredError("multimodal/processed_material_demoted", {
      user_id: user.id,
      reason: processedMaterialNormalization.reason,
      previous_common_name: processedMaterialNormalization.previousCommonName ??
        null,
      previous_scientific_name:
        processedMaterialNormalization.previousScientificName ?? null,
    });
  }
  if (!parsedData.is_biological_subject) {
    parsedData.is_invasive = undefined;
    parsedData.invasive_status_region = undefined;
    parsedData.invasive_rationale = undefined;
    parsedData.invasive_confidence = undefined;
    parsedData.sex = undefined;
    parsedData.sex_confidence = undefined;
    parsedData.sex_evidence = undefined;
  } else if (
    parsedData.sex == null ||
    parsedData.sex === "cannot_determine" ||
    parsedData.sex === "not_applicable"
  ) {
    parsedData.sex_confidence = undefined;
    parsedData.sex_evidence = undefined;
  }
  const hasInvasiveLocationContext =
    (safeGpsLat != null && safeGpsLon != null) ||
    (typeof semanticLocation === "string" &&
      semanticLocation.trim().length > 0);
  if (parsedData.is_biological_subject && !hasInvasiveLocationContext) {
    parsedData.is_invasive = false;
    parsedData.invasive_status_region ??= "Unavailable";
    parsedData.invasive_rationale ??=
      "Location context was unavailable, so Naturebook could not make a region-specific invasive assessment.";
    parsedData.invasive_confidence = undefined;
  }

  parsedData.blur_score = Math.max(
    0,
    (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10,
  );

  let referenceImageUrl: string | null = null;
  let wikipediaUrl: string | null = null;
  let wikipediaOverview: string | null = null;
  let alternativeCommonNames: string[] | null = null;

  const isIdentifiedBio =
    !!(parsedData.is_biological_subject && parsedData.scientific_name);
  let cachedSpecies: CachedSpeciesRow | null = null;
  let externalData:
    | Awaited<ReturnType<typeof fetchExternalEnrichment>>
    | null = null;
  let missingCandidates: string[] = [];

  let payloadReadyForClient: ClientPayload = {
    scan_id: generatedScanId,
    is_biological_subject: parsedData.is_biological_subject,
    is_live_capture: parsedData.is_live_capture,
    scientific_name: parsedData.scientific_name,
    common_name: parsedData.common_name,
    confidence_score: parsedData.confidence_score,
    blur_score: parsedData.blur_score,
    ecology_type: parsedData.ecology_type,
    is_invasive: parsedData.is_invasive,
    invasive_status_region: parsedData.invasive_status_region,
    invasive_rationale: parsedData.invasive_rationale,
    invasive_confidence: parsedData.invasive_confidence,
    life_stage: parsedData.life_stage ?? "unknown",
    sex: parsedData.sex,
    sex_confidence: parsedData.sex_confidence,
    sex_evidence: parsedData.sex_evidence,
    inference_tier: inferenceTier,
    candidates: parsedData.candidates,
    image_quality: parsedData.image_quality,
    pet_identification: parsedData.pet_identification,
    ai_reasoning: parsedData.ai_reasoning,
    insight_data: {
      ai_reasoning: parsedData.ai_reasoning,
      hazard_type: "none",
    },
    extracted_visual_traits: parsedData.extracted_visual_traits,
    reference_image_url: referenceImageUrl,
    wikipedia_url: wikipediaUrl,
    wikipedia_overview: wikipediaOverview,
    alternative_common_names: alternativeCommonNames,
  };

  if ((parsedData.confidence_score ?? 0.0) >= diagnosticTrigger) {
    payloadReadyForClient.candidates = null;
  }

  const hasCandidates = Array.isArray(payloadReadyForClient.candidates) &&
    payloadReadyForClient.candidates.length > 0;

  const dictionaryHydrationStart = performance.now();
  const candidateScientificNames = hasCandidates
    ? payloadReadyForClient.candidates!.map((candidate) =>
      candidate.scientific_name
    )
    : [];
  let commonNameMap = new Map<string, string>();
  let fetchedCachedSpecies: CachedSpeciesRow | null = null;
  if (isIdentifiedBio || hasCandidates) {
    try {
      const hydration = await fetchIdentificationDictionaryHydration(
        isIdentifiedBio ? parsedData.scientific_name! : null,
        candidateScientificNames,
        supabaseAdmin,
      );
      commonNameMap = hydration.candidateCommonNames;
      fetchedCachedSpecies = hydration.cachedSpecies;
    } catch (error) {
      logStructuredError("multimodal/dictionary_hydration_fallback", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: error instanceof Error ? error.message : String(error),
      });
      [commonNameMap, fetchedCachedSpecies] = await Promise.all([
        hasCandidates
          ? fetchCandidateCommonNames(candidateScientificNames, supabaseAdmin)
          : Promise.resolve(new Map<string, string>()),
        isIdentifiedBio
          ? fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin)
            .catch(
              (err) => {
                console.error("Dictionary hydration fallback error:", err);
                return null;
              },
            )
          : Promise.resolve(null),
      ]);
    }
  }
  const dictionaryHydrationMs = performance.now() - dictionaryHydrationStart;

  if (hasCandidates) {
    const candidateNames = payloadReadyForClient.candidates!.map((
      candidate,
    ) => candidate.scientific_name);
    missingCandidates = candidateNames.filter((name) =>
      !commonNameMap.has(name)
    );
    if (commonNameMap.size > 0) {
      payloadReadyForClient.candidates = payloadReadyForClient.candidates!
        .map((candidate) => ({
          ...candidate,
          common_name: commonNameMap.get(candidate.scientific_name),
        }));
    }
  }

  if (isIdentifiedBio) {
    cachedSpecies = fetchedCachedSpecies;
    payloadReadyForClient.is_new_to_merian_dictionary = isNewToMerianDictionary(
      isIdentifiedBio,
      cachedSpecies,
    );

    if (cachedSpecies && normalizeTaxonomyValue(cachedSpecies.kingdom)) {
      payloadReadyForClient = hydratePayloadFromCachedSpecies(
        payloadReadyForClient,
        cachedSpecies,
      );
      referenceImageUrl = payloadReadyForClient.reference_image_url ?? null;
      wikipediaUrl = payloadReadyForClient.wikipedia_url ?? null;
      wikipediaOverview = payloadReadyForClient.wikipedia_overview ?? null;
      alternativeCommonNames = payloadReadyForClient.alternative_common_names ??
        null;
    }
  }

  payloadReadyForClient.reference_image_url = referenceImageUrl;
  payloadReadyForClient.wikipedia_url = wikipediaUrl;
  payloadReadyForClient.wikipedia_overview = wikipediaOverview;
  payloadReadyForClient.alternative_common_names = alternativeCommonNames;

  const persistedObservationContext = observation_contexts.find((context) =>
    context != null && typeof context === "object" && !Array.isArray(context)
  ) as Record<string, unknown> | undefined;

  const requireDurableVideo = videoR2ObjectKeys.length > 0;
  if (requireDurableVideo) {
    await updateIngestionJobBestEffort(
      "finalizing",
      "ai_inference_complete",
      { leaseSeconds: 300 },
    );
  }

  const runBackgroundIngestion = async () => {
    let modResult:
      | Awaited<ReturnType<typeof evaluateAndProcessPayload>>
      | undefined;
    let scanInserted = false;
    let videoStorageUrls: string[] = [];
    let promotedAudioUrlsForRollback: string[] = [];
    const markUploadAssetsFailedBestEffort = async (
      storageKeys: string[],
      failureReason: string,
    ) => {
      try {
        await markStagedScanMediaAssetsFailed(
          {
            userId: user.id,
            storageKeys,
            failureReason,
          },
          supabaseAdmin,
        );
      } catch (error) {
        logStructuredError("multimodal/upload_assets_mark_failed_error", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    };

    const markUploadAssetsPromotedBestEffort = async (
      urlsByStorageKey: Map<string, string>,
    ) => {
      try {
        await markStagedScanMediaAssetsPromoted(
          {
            userId: user.id,
            scanId: generatedScanId,
            promotedUrlsByStorageKey: urlsByStorageKey,
          },
          supabaseAdmin,
        );
      } catch (error) {
        logStructuredError("multimodal/upload_assets_mark_promoted_error", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    };

    const markUploadAssetsDeletedBestEffort = async (
      storageKeys: string[],
    ) => {
      try {
        await markStagedScanMediaAssetsDeleted(
          {
            userId: user.id,
            scanId: generatedScanId,
            storageKeys,
          },
          supabaseAdmin,
        );
      } catch (error) {
        logStructuredError("multimodal/upload_assets_mark_deleted_error", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    };

    try {
      if (!requireDurableVideo) {
        await updateIngestionJobBestEffort(
          "finalizing",
          "ai_inference_complete",
          { leaseSeconds: 600 },
        );
      }
      await updateIngestionJobBestEffort(
        "finalizing",
        "background_ingestion_started",
        { leaseSeconds: requireDurableVideo ? 300 : 600 },
      );
      await upsertGhostUserIfMissing(user.id, supabaseAdmin);
      const hasImagePayload = imageBase64s.length > 0 ||
        r2ObjectKeys.length > 0;
      if (hasImagePayload) {
        await updateIngestionJobBestEffort(
          "finalizing",
          "moderation_started",
          { leaseSeconds: requireDurableVideo ? 300 : 600 },
        );
        modResult = await evaluateAndProcessPayload(
          user.id,
          r2ObjectKeys,
          imageBase64s,
          finishReason,
          safetyRatings,
          userTier,
          videoR2ObjectKeys,
        );
        if (modResult.status === "ERROR") {
          console.error(
            "Multimodal moderation pipeline returned ERROR. Halting background data ingestion.",
          );
          await markUploadAssetsFailedBestEffort(
            [...r2ObjectKeys, ...videoR2ObjectKeys, ...audioR2ObjectKeys],
            "moderation_pipeline_error",
          );
          await updateIngestionJobBestEffort(
            "failed_retryable",
            "moderation_pipeline_error",
            {
              lastError: "Multimodal moderation pipeline failed.",
              retryAfter: retryAfterIso(),
            },
          );
          if (requireDurableVideo) {
            throw new Error("Multimodal moderation pipeline failed.");
          }
          return;
        }
        if (
          modResult.status === "SHADOWBANNED" ||
          modResult.status === "DELETED_WARNING"
        ) {
          console.error(
            "Multimodal media flagged by safety moderation. Halting background data ingestion.",
          );
          await markUploadAssetsFailedBestEffort(
            [...r2ObjectKeys, ...videoR2ObjectKeys, ...audioR2ObjectKeys],
            "moderation_rejected",
          );
          await updateIngestionJobBestEffort(
            "failed_terminal",
            "moderation_rejected",
            { lastError: "Multimodal media rejected by moderation." },
          );
          if (requireDurableVideo) {
            throw new Error("Multimodal media rejected by moderation.");
          }
          return;
        }
      }

      let speciesId: string | null = null;
      let audioStorageUrls: string[] = [];
      let standaloneAudioStorageKeys: string[] = [];
      let companionAudioStorageKeys: string[] = [];
      if (videoR2ObjectKeys.length > 0) {
        try {
          await updateIngestionJobBestEffort(
            "finalizing",
            "video_promotion_started",
            { leaseSeconds: 300 },
          );
          videoStorageUrls = await promoteSafeMedia({
            userId: user.id,
            r2ObjectKeys: videoR2ObjectKeys,
            imageBase64s: undefined,
            userTier,
            r2Config: getR2Config(),
          });
          if (videoStorageUrls.length !== videoR2ObjectKeys.length) {
            throw new Error(
              `Video promotion returned ${videoStorageUrls.length}/${videoR2ObjectKeys.length} URL(s).`,
            );
          }
        } catch (err) {
          logStructuredError("multimodal/video_promotion_failed", {
            user_id: user.id,
            error: String(err),
          });
          await updateIngestionJobBestEffort(
            "failed_retryable",
            "video_promotion_failed",
            {
              lastError: err instanceof Error ? err.message : String(err),
              retryAfter: retryAfterIso(),
            },
          );
          throw err;
        }
      }

      if (audioR2ObjectKeys.length > 0 || audioBase64s.length > 0) {
        const promotedAudioUrls = await promoteSafeMedia({
          userId: user.id,
          r2ObjectKeys: audioR2ObjectKeys.length > 0
            ? audioR2ObjectKeys
            : undefined,
          imageBase64s: audioBase64s.length > 0 ? audioBase64s : undefined,
          userTier,
          r2Config: getR2Config(),
          contentType: "audio/wav",
          fallbackExtension: "wav",
        });
        promotedAudioUrlsForRollback = promotedAudioUrls;
        const expectedAudioCount = audioR2ObjectKeys.length > 0
          ? audioR2ObjectKeys.length
          : audioBase64s.length;
        if (promotedAudioUrls.length !== expectedAudioCount) {
          throw new Error(
            `Audio promotion returned ${promotedAudioUrls.length}/${expectedAudioCount} URL(s).`,
          );
        }
        const standaloneIndexes = normalizedAudioMediaItems.flatMap(
          (descriptor, index) => descriptor.kind === "audio" ? [index] : [],
        );
        audioStorageUrls = standaloneIndexes.flatMap((index) =>
          promotedAudioUrls[index] ? [promotedAudioUrls[index]] : []
        );
        standaloneAudioStorageKeys = standaloneIndexes.flatMap((index) =>
          audioR2ObjectKeys[index] ? [audioR2ObjectKeys[index]] : []
        );
        companionAudioStorageKeys = audioR2ObjectKeys.filter((_, index) =>
          !standaloneIndexes.includes(index)
        );
        const companionAudioUrls = promotedAudioUrls.filter((_, index) =>
          !standaloneIndexes.includes(index)
        );
        if (companionAudioUrls.length > 0) {
          const r2Config = getR2Config();
          await Promise.allSettled(
            companionAudioUrls.map((url) =>
              deleteR2Object(
                url.replace("https://media.merian.app/", ""),
                r2Config,
              )
            ),
          );
        }
      }

      if (
        isIdentifiedBio &&
        (!cachedSpecies || !normalizeTaxonomyValue(cachedSpecies.kingdom))
      ) {
        try {
          externalData = await fetchExternalEnrichment(
            parsedData.scientific_name!,
          );
        } catch (error) {
          console.error("Background primary enrichment error:", error);
        }
      }

      const needsGroupTags = isIdentifiedBio &&
        !cachedSpecies?.group_tags?.length;
      const groupTagsPromise = needsGroupTags
        ? fetchGroupTags(user, parsedData.scientific_name!, supabaseAdmin)
        : Promise.resolve(null);

      if (isIdentifiedBio) {
        if (cachedSpecies && normalizeTaxonomyValue(cachedSpecies.kingdom)) {
          speciesId = cachedSpecies.id;
        } else if (externalData) {
          const freshSpecies = await fetchCachedSpecies(
            parsedData.scientific_name!,
            supabaseAdmin,
          );
          const newCommonNames = mergeSpeciesCommonNames(
            freshSpecies?.common_names,
            payloadReadyForClient.common_name,
          );
          const upsertedId = await upsertSpeciesDictionary(
            {
              scientific_name: parsedData.scientific_name!,
              common_names: newCommonNames,
              kingdom: coalesceTaxonomyValue(freshSpecies?.kingdom),
              phylum: coalesceTaxonomyValue(freshSpecies?.phylum),
              class: coalesceTaxonomyValue(freshSpecies?.class),
              order: coalesceTaxonomyValue(freshSpecies?.order),
              family: coalesceTaxonomyValue(freshSpecies?.family),
              genus: coalesceTaxonomyValue(freshSpecies?.genus),
              native_region: "Unknown",
              wikipedia_url: externalData.wikipediaUrl,
              wikipedia_overview: externalData.wikiExtract,
              gbif_taxon_key: externalData.gbifKey,
              reference_image_url: externalData.referenceImageUrl,
              alternative_common_names: externalData.alternativeCommonNames,
            },
            supabaseAdmin,
          );
          speciesId = upsertedId || freshSpecies?.id || null;
        } else {
          speciesId = cachedSpecies?.id || null;
        }
      }

      const capturedMedia = buildCapturedMediaManifest(
        modResult?.publicUrls ?? [],
        videoStorageUrls,
        audioStorageUrls,
        normalizedVisualMediaItems,
        normalizedAudioMediaItems,
      );

      await updateIngestionJobBestEffort(
        "finalizing",
        "scan_insert_started",
        { leaseSeconds: 300 },
      );
      await insertScan(
        {
          id: generatedScanId,
          user_id: user.id,
          species_id: speciesId,
          timestamp: timestamp ?? undefined,
          gps_lat_exact: safeGpsLat,
          gps_long_exact: safeGpsLon,
          gps_elevation: gpsElevation ?? null,
          ai_confidence_score: parsedData.confidence_score,
          is_biological_subject: parsedData.is_biological_subject,
          blur_score: parsedData.blur_score,
          ecology_type: parsedData.ecology_type,
          is_invasive: parsedData.is_invasive,
          invasive_status_region: parsedData.invasive_status_region ?? null,
          invasive_rationale: parsedData.invasive_rationale ?? null,
          invasive_confidence: parsedData.invasive_confidence ?? null,
          weather_condition: weatherCondition ?? undefined,
          weather_temperature_f: weatherTemperatureF ?? undefined,
          semantic_location: semanticLocation ?? undefined,
          public_location_label: publicExploreLocationLabel ?? undefined,
          geoprivacy: scanGeoprivacy ?? undefined,
          device_locale: deviceLocale ?? undefined,
          device_time_zone: deviceTimeZone ?? undefined,
          current_month: currentMonth ?? null,
          time_of_day: timeOfDay ?? undefined,
          depth_scale_text: depthScaleText ?? undefined,
          ai_reasoning: parsedData.ai_reasoning ?? null,
          extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
          colors: [],
          llm_prompt_tokens: llmPromptTokens,
          llm_candidate_tokens: llmCandidateTokens,
          llm_thinking_tokens: llmThinkingTokens,
          llm_cached_tokens: null,
          llm_total_tokens: llmTotalTokens,
          llm_usage_metadata: llmUsageMetadata,
          image_storage_urls: modResult?.publicUrls ?? [],
          video_storage_urls: videoStorageUrls,
          audio_storage_urls: audioStorageUrls,
          captured_media: capturedMedia,
          life_stage: parsedData.life_stage ?? "unknown",
          reproductive_condition: parsedData.reproductive_condition ??
            "not_applicable",
          sex: parsedData.sex ?? null,
          sex_confidence: parsedData.sex_confidence ?? null,
          sex_evidence: parsedData.sex_evidence ?? null,
          individual_count: parsedData.individual_count ?? null,
          ecological_interactions: parsedData.ecological_interactions ?? [],
          estimated_size_cm:
            (estimatedSizeCm != null && Number.isFinite(estimatedSizeCm) &&
                estimatedSizeCm > 0)
              ? Math.min(estimatedSizeCm, 50000)
              : null,
          inference_tier: inferenceTier,
          candidates: payloadReadyForClient.candidates ?? null,
          image_quality_score: parsedData.image_quality?.overall_score ??
            null,
          is_live_capture: parsedData.is_live_capture,
          pet_identification: parsedData.pet_identification ?? null,
          user_observation_context: persistedObservationContext ?? null,
        },
        supabaseAdmin,
      );
      scanInserted = true;
      await updateIngestionJobBestEffort(
        "complete",
        "scan_inserted",
      );
      await markUploadAssetsPromotedBestEffort(
        new Map([
          ...publicUrlsByStorageKey(
            r2ObjectKeys,
            modResult?.publicUrls ?? [],
          ),
          ...publicUrlsByStorageKey(videoR2ObjectKeys, videoStorageUrls),
          ...publicUrlsByStorageKey(
            standaloneAudioStorageKeys,
            audioStorageUrls,
          ),
        ]),
      );
      await markUploadAssetsDeletedBestEffort(companionAudioStorageKeys);
      await refreshScanMediaAssetsBestEffort(generatedScanId, supabaseAdmin);
      if (audioStorageUrls.length > 0) {
        // Audio is a required durable asset, so unlike the visual compatibility
        // refresh above, standalone-audio normalization must fail ingestion if
        // the canonical database refresh cannot create its ready rows.
        await refreshScanMediaAssets(generatedScanId, supabaseAdmin);
      }

      let candidateEnrichmentTask: Promise<void> = Promise.resolve();
      if (missingCandidates.length > 0) {
        const capturedCandidates = missingCandidates.slice();
        candidateEnrichmentTask = Promise.allSettled(
          capturedCandidates.map(async (candidateName) => {
            const candidateExternalData = await fetchExternalEnrichment(
              candidateName,
            );

            const primaryEnName = (candidateExternalData.wikiTitle &&
                candidateExternalData.wikiTitle.toLowerCase() !==
                  candidateName.toLowerCase())
              ? candidateExternalData.wikiTitle.replace(/\s*\([^)]+\)$/, "")
                .trim()
              : (candidateExternalData.alternativeCommonNames[0] ?? null);
            const freshCandidateSpecies = await fetchCachedSpecies(
              candidateName,
              supabaseAdmin,
            );
            const candidateCommonNames = mergeSpeciesCommonNames(
              freshCandidateSpecies?.common_names,
              primaryEnName,
            );

            const primaryEnLower = (candidateCommonNames.en ?? "")
              .toLowerCase();
            const newAltNames: string[] | null =
              candidateExternalData.alternativeCommonNames.length > 0
                ? candidateExternalData.alternativeCommonNames.filter((
                  name,
                ) => name.toLowerCase() !== primaryEnLower)
                : null;

            await upsertSpeciesDictionary(
              {
                scientific_name: candidateName,
                common_names: candidateCommonNames,
                alternative_common_names: newAltNames,
                kingdom: null,
                phylum: null,
                class: null,
                order: null,
                family: null,
                genus: null,
                wikipedia_overview: candidateExternalData.wikiExtract ?? null,
                hazard_type: "none",
                native_region: "Unknown",
                iucn_red_list_status: "not_evaluated",
                habitat_description: undefined,
                wikipedia_url: candidateExternalData.wikipediaUrl,
                gbif_taxon_key: candidateExternalData.gbifKey,
                reference_image_url: candidateExternalData.referenceImageUrl,
              },
              supabaseAdmin,
            );
          }),
        ).then((results) => {
          for (let i = 0; i < results.length; i++) {
            const result = results[i];
            if (result.status === "rejected") {
              console.error(
                `[multimodal/candidate_enrichment] Failed to enrich ${
                  capturedCandidates[i]
                }: ${
                  result.reason instanceof Error
                    ? result.reason.message
                    : String(result.reason)
                }`,
              );
            }
          }
        });
      }

      trackPostHogEvent(user.id, "scan_completed", {
        scan_id: generatedScanId,
        inference_tier: inferenceTier,
        tier: userTier,
        ...tierTelemetryProperties(tierResolution),
        media_type: mediaTelemetry.mediaType,
        media_kinds: [
          mediaTelemetry.hasImage ? "image" : null,
          mediaTelemetry.hasVideo ? "video" : null,
          processedAudios.length > 0 ? "audio" : null,
          hasObservationContextText ? "description" : null,
        ].filter((kind): kind is string => kind != null),
        has_image: mediaTelemetry.hasImage,
        has_video: mediaTelemetry.hasVideo,
        has_audio: processedAudios.length > 0,
        has_description: hasObservationContextText,
        image_count: mediaTelemetry.imageCount,
        video_clip_count: mediaTelemetry.videoClipCount,
        video_frame_count: mediaTelemetry.declaredVideoFrameCount,
        video_inference_frame_count: mediaTelemetry.videoInferenceFrameCount,
        durable_video_required: requireDurableVideo,
        video_r2_object_key_count: videoR2ObjectKeys.length,
        video_storage_url_count: videoStorageUrls.length,
        captured_media_item_count: capturedMedia?.length ?? 0,
        captured_media_video_count: capturedMediaVideoCount(capturedMedia),
        audio_clip_count: processedAudios.length,
        llm_model: targetModel,
        llm_prompt_tokens: llmPromptTokens,
        llm_candidate_tokens: llmCandidateTokens,
        llm_thinking_tokens: llmThinkingTokens,
        llm_total_tokens: llmTotalTokens,
        video_llm_prompt_tokens: mediaTelemetry.hasVideo
          ? llmPromptTokens
          : null,
        video_llm_candidate_tokens: mediaTelemetry.hasVideo
          ? llmCandidateTokens
          : null,
        video_llm_thinking_tokens: mediaTelemetry.hasVideo
          ? llmThinkingTokens
          : null,
        video_llm_total_tokens: mediaTelemetry.hasVideo ? llmTotalTokens : null,
        video_token_accounting: mediaTelemetry.hasVideo
          ? "full_multimodal_request"
          : null,
        is_identified: isIdentifiedBio,
        species_name: parsedData.scientific_name || null,
        gemini_latency_ms: geminiLatencyMs,
      }).catch((e) => console.error("PostHog tracking failed:", e));

      const runOptionalSpeciesWrites = async () => {
        try {
          const groupTagsResult = await groupTagsPromise;
          const bgWriteResults = await Promise.allSettled([
            needsGroupTags && groupTagsResult?.group_tags?.length
              ? updateGroupTags(
                parsedData.scientific_name!,
                groupTagsResult.group_tags,
                supabaseAdmin,
              )
              : Promise.resolve(),
            candidateEnrichmentTask,
          ]);
          for (const result of bgWriteResults) {
            if (result.status === "rejected") {
              console.error(
                JSON.stringify({
                  event: "multimodal/bg_species_write_failed",
                  scan_id: generatedScanId,
                  error: result.reason instanceof Error
                    ? result.reason.message
                    : String(result.reason),
                  ts: new Date().toISOString(),
                }),
              );
            }
          }
        } catch (error) {
          console.error(
            JSON.stringify({
              event: "multimodal/bg_species_write_failed",
              scan_id: generatedScanId,
              error: error instanceof Error ? error.message : String(error),
              ts: new Date().toISOString(),
            }),
          );
        }
      };

      if (requireDurableVideo) {
        runBackground(runOptionalSpeciesWrites());
      } else {
        await runOptionalSpeciesWrites();
      }
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      const terminalFailure = errorMsg.toLowerCase().includes("rejected");
      await updateIngestionJobBestEffort(
        terminalFailure ? "failed_terminal" : "failed_retryable",
        terminalFailure ? "moderation_rejected" : "background_ingestion_failed",
        {
          lastError: errorMsg,
          retryAfter: terminalFailure ? null : retryAfterIso(),
        },
      );
      logStructuredError("multimodal/background_ingestion_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: errorMsg,
        scan_inserted: scanInserted,
      });

      if (!scanInserted) {
        await markUploadAssetsFailedBestEffort(
          [...r2ObjectKeys, ...videoR2ObjectKeys, ...audioR2ObjectKeys],
          "scan_finalization_failed",
        );
      }

      // Dead-Letter Fallback
      if (!scanInserted) {
        try {
          await supabaseAdmin
            .from("failed_scan_ingestions")
            .insert({
              scan_id: generatedScanId,
              user_id: user.id,
              error_message: errorMsg,
            });
        } catch (dlErr) {
          logStructuredError("multimodal/dead_letter_write_failed", {
            scan_id: generatedScanId,
            error: String(dlErr),
          });
        }
      }

      const promotedPublicUrls = [
        ...(modResult?.publicUrls ?? []),
        ...videoStorageUrls,
        ...promotedAudioUrlsForRollback,
      ];
      if (!scanInserted && promotedPublicUrls.length) {
        const r2Config = getR2Config();
        const keysToPurge = promotedPublicUrls.map((url: string) =>
          url.replace("https://media.merian.app/", "")
        );
        const rollbackResults = await Promise.allSettled(
          keysToPurge.map((key: string) => deleteR2Object(key, r2Config)),
        );
        const failedRollbacks = rollbackResults.filter((r) =>
          r.status === "rejected"
        );
        if (failedRollbacks.length > 0) {
          logStructuredError("multimodal/r2_rollback_partial_failure", {
            scan_id: generatedScanId,
            user_id: user.id,
            failed_count: failedRollbacks.length,
            total_count: keysToPurge.length,
          });
        }
      }
      if (requireDurableVideo) {
        throw e;
      }
    }
  };

  if (requireDurableVideo) {
    try {
      await runBackgroundIngestion();
    } catch (error) {
      logStructuredError("multimodal/video_durable_insert_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: error instanceof Error ? error.message : String(error),
      });
      trackPostHogEvent(user.id, "video_scan_persistence_failed", {
        scan_id: generatedScanId,
        inference_tier: inferenceTier,
        tier: userTier,
        ...tierTelemetryProperties(tierResolution),
        video_r2_object_key_count: videoR2ObjectKeys.length,
        error: error instanceof Error ? error.message : String(error),
      }).catch((e) => console.error("PostHog tracking failed:", e));
      return jsonResponse(
        { error: "Video media could not be saved. Please retry." },
        503,
      );
    }
  } else {
    runBackground(runBackgroundIngestion());
  }

  const edgeTotalMs = Date.now() - fnStart + authDurationMs;
  const postGeminiMs = Math.max(Date.now() - geminiCompletedAt, 0);
  const payloadBytes = Number(req.headers.get("content-length")) || null;
  const edgeRegion = Deno.env.get("SB_REGION") ??
    req.headers.get("x-sb-edge-region") ?? "unknown";
  const constrainedNetwork =
    req.headers.get("x-merian-constrained-network") === "true";
  console.log(JSON.stringify({
    event: "multimodal/latency",
    tier: userTier,
    inference_tier: inferenceTier,
    model: targetModel,
    image_count: mediaTelemetry.imageCount,
    payload_bytes: payloadBytes,
    edge_region: edgeRegion,
    constrained_network: constrainedNetwork,
    auth_ms: Math.round(authDurationMs),
    body_read_ms: Math.round(bodyReadMs),
    tier_resolution_ms: Math.round(tierMs),
    pre_gemini_db_ms: Math.round(preGeminiDbMs),
    gemini_latency_ms: geminiLatencyMs,
    dictionary_hydration_ms: Math.round(dictionaryHydrationMs),
    post_gemini_ms: Math.round(postGeminiMs),
    non_gemini_ms: Math.max(edgeTotalMs - geminiLatencyMs, 0),
    edge_total_ms: edgeTotalMs,
    ts: new Date().toISOString(),
  }));

  return jsonResponse(
    { success: true, data: payloadReadyForClient },
    200,
    {
      "Server-Timing": serverTimingValue([
        { name: "body_read", durationMs: bodyReadMs },
        { name: "tier", durationMs: tierMs },
        { name: "pre_gemini_db", durationMs: preGeminiDbMs },
        { name: "gemini", durationMs: geminiLatencyMs },
        { name: "dictionary", durationMs: dictionaryHydrationMs },
        { name: "post_gemini", durationMs: postGeminiMs },
        { name: "edge_total", durationMs: edgeTotalMs },
      ]),
      "X-Merian-Edge-Region": edgeRegion,
    },
  );
}

async function tryHandleInternalReplayRequest(
  req: Request,
): Promise<Response | null> {
  if (req.headers.get(INTERNAL_REPLAY_HEADER) !== "scan-ingestion") {
    return null;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const auth = await authorizeServiceRoleRequest(req, {
    supabaseUrl,
    envServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  });
  if (!auth.ok || !auth.token) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const userId = req.headers.get(INTERNAL_REPLAY_USER_HEADER)?.trim() ?? "";
  if (userId.length === 0) {
    return jsonResponse({ error: "Missing replay user id." }, 400);
  }

  const supabaseAdmin = createClient(supabaseUrl, auth.token, {
    global: {
      headers: {
        Authorization: `Bearer ${auth.token}`,
        apikey: auth.token,
      },
    },
  });

  return await handleIdentifyMultimodalRequest(
    req,
    { id: userId } as User,
    supabaseAdmin,
  );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const replayResponse = await tryHandleInternalReplayRequest(req);
  if (replayResponse) return replayResponse;

  return withEdgeHandler(
    req,
    (user, supabaseAdmin, context) =>
      handleIdentifyMultimodalRequest(
        req,
        user,
        supabaseAdmin,
        context.authDurationMs,
      ),
    { authenticate: requireClaimsAuth },
  );
});
