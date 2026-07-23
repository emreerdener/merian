import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

import { sanitizeScientificName } from "../identify/sanitize.ts";
import {
  MEDIA_BUDGETS,
  validateAudioClipCount,
  validateInlineAudioBase64Budget,
  validateStagingObjectKey,
} from "../_shared/mediaBudgets.ts";

type R2KeyError = "path_traversal" | "wrong_user" | null;

const VALID_LIFE_STAGES = new Set([
  "egg",
  "larva",
  "pupa",
  "nymph",
  "juvenile",
  "subadult",
  "adult",
  "seedling",
  "sapling",
  "unknown",
]);

const VALID_REPRODUCTIVE_CONDITIONS = new Set([
  "flowering",
  "fruiting",
  "budding",
  "vegetative",
  "sporing",
  "pregnant",
  "gravid",
  "mating",
  "spawning",
  "nesting",
  "dormant",
  "not_applicable",
]);

const VALID_SEX_VALUES = new Set([
  "female",
  "male",
  "hermaphrodite",
  "mixed",
  "cannot_determine",
  "not_applicable",
]);

// ---------------------------------------------------------------------------
// Pure helpers mirroring identify-multimodal/index.ts without loading Deno serve().
// ---------------------------------------------------------------------------

function resolveSystemInstruction(
  hasImages: boolean,
  hasAudio: boolean,
): "BLENDED" | "VISION" | "BIOACOUSTIC" | "DESCRIBE" {
  if (hasImages && hasAudio) return "BLENDED";
  if (hasImages) return "VISION";
  if (hasAudio) return "BIOACOUSTIC";
  return "DESCRIBE";
}

function isPayloadEmpty(
  partsArrayLength: number,
  hasObservationContextText: boolean,
): boolean {
  return partsArrayLength === 1 && !hasObservationContextText;
}

function validateR2ObjectKey(key: string, userId: string): R2KeyError {
  return validateStagingObjectKey(key, userId);
}

function validateAudioPayloadShape(
  audioR2ObjectKeys: string[],
  audioBase64s: string[],
): number | null {
  const clipCountError = validateAudioClipCount(
    audioR2ObjectKeys.length,
    audioBase64s.length,
  );
  if (clipCountError) return clipCountError.status;
  if (
    audioBase64s.some((payload) => validateInlineAudioBase64Budget(payload))
  ) {
    return 413;
  }
  return null;
}

function safeGpsLat(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
      v >= -90 && v <= 90
    ? v
    : null;
}

function safeGpsLon(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
      v >= -180 && v <= 180
    ? v
    : null;
}

function resolveGeneratedScanId(client_scan_id: unknown): string {
  return typeof client_scan_id === "string" && client_scan_id.length > 0
    ? client_scan_id
    : crypto.randomUUID();
}

function normalizeCurrentMonth(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const month = Math.trunc(value);
    return month >= 1 && month <= 12 ? month : null;
  }

  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^\d{1,2}$/.test(trimmed)) {
      const month = Number(trimmed);
      return month >= 1 && month <= 12 ? month : null;
    }
  }

  return null;
}

function normalizeTelemetry(body: Record<string, unknown>) {
  return {
    gpsLatitude: body.gpsLatitude ?? body.gps_latitude ?? null,
    gpsLongitude: body.gpsLongitude ?? body.gps_longitude ?? null,
    gpsElevation: body.gpsElevation ?? body.gps_elevation ?? null,
    semanticLocation: body.semanticLocation ?? body.semantic_location ?? null,
    weatherCondition: body.weatherCondition ?? body.weather_condition ?? null,
    weatherTemperatureF: body.weatherTemperatureF ??
      body.weather_temperature_f ?? null,
    deviceLocale: body.deviceLocale ?? body.device_locale ?? null,
    deviceTimeZone: body.deviceTimeZone ?? body.device_time_zone ?? null,
    deviceRegion: body.deviceRegion ?? body.device_region ?? null,
    currentMonth: normalizeCurrentMonth(
      body.currentMonth ?? body.current_month ?? null,
    ),
    timeOfDay: body.timeOfDay ?? body.time_of_day ?? null,
    depthScaleText: body.depthScaleText ?? body.depth_scale_text ?? null,
    zoomFactor: body.zoomFactor ?? null,
    estimatedSizeCm: body.estimatedSizeCm ?? body.estimated_size_cm ?? null,
  };
}

function mergeObservationContexts(
  contexts: Array<Record<string, unknown>>,
): string[] {
  return contexts
    .map((context) => {
      const freeText = typeof context.freeText === "string"
        ? context.freeText.trim()
        : "";
      const snakeCase = typeof context.free_text === "string"
        ? context.free_text.trim()
        : "";
      return freeText || snakeCase || null;
    })
    .filter((text): text is string => text != null && text.length > 0);
}

function sanitizeCount(v: unknown): number | undefined {
  if (v == null || typeof v !== "number" || !Number.isFinite(v) || v <= 0) {
    return undefined;
  }
  return Math.min(Math.round(v), 99999);
}

function telemetryCount(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.trunc(value);
}

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

function optionalIndex(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return undefined;
  }
  return Math.trunc(value);
}

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

    const item = rawItem as Record<string, unknown>;
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

    const item = rawItem as Record<string, unknown>;
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

function sanitizeReasoning(text: string): string {
  return text.length > 2000 ? text.slice(0, 2000) : text;
}

function sanitizeLifeStage(value: string | undefined): string {
  if (value == null) return "unknown";
  return VALID_LIFE_STAGES.has(value) ? value : "unknown";
}

function sanitizeReproductiveCondition(value: string | undefined): string {
  if (value == null) return "not_applicable";
  return VALID_REPRODUCTIVE_CONDITIONS.has(value) ? value : "not_applicable";
}

function sanitizeSex(value: string | undefined): string {
  if (value == null) return "cannot_determine";
  return VALID_SEX_VALUES.has(value) ? value : "cannot_determine";
}

function sanitizeCandidates(
  candidates: Array<{ scientific_name: string; confidence_score?: number }>,
) {
  return candidates
    .map((candidate) => ({
      ...candidate,
      scientific_name: sanitizeScientificName(candidate.scientific_name),
    }))
    .slice(0, 5);
}

function resolveReturnedCandidates<T>(
  candidates: T[] | null | undefined,
  confidenceScore: number | null | undefined,
  diagnosticTrigger: number,
): T[] | null {
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  if ((confidenceScore ?? 0) >= diagnosticTrigger) return null;
  return candidates;
}

// ---------------------------------------------------------------------------
// Dispatch rule tests
// ---------------------------------------------------------------------------

Deno.test("dispatch - images + audio -> BLENDED instruction", () => {
  assertEquals(resolveSystemInstruction(true, true), "BLENDED");
});

Deno.test("dispatch - images only -> VISION instruction", () => {
  assertEquals(resolveSystemInstruction(true, false), "VISION");
});

Deno.test("dispatch - audio only -> BIOACOUSTIC instruction", () => {
  assertEquals(resolveSystemInstruction(false, true), "BIOACOUSTIC");
});

Deno.test("dispatch - no images, no audio -> DESCRIBE instruction", () => {
  assertEquals(resolveSystemInstruction(false, false), "DESCRIBE");
});

// ---------------------------------------------------------------------------
// Empty payload guard
// ---------------------------------------------------------------------------

Deno.test("payload guard - only telemetry and no context text -> reject", () => {
  assert(isPayloadEmpty(1, false));
});

Deno.test("payload guard - context text + telemetry -> accept", () => {
  assert(!isPayloadEmpty(2, true));
});

Deno.test("payload guard - image + telemetry -> accept", () => {
  assert(!isPayloadEmpty(2, false));
});

// ---------------------------------------------------------------------------
// R2 key validation
// ---------------------------------------------------------------------------

Deno.test("IDOR guard - key belonging to correct user passes", () => {
  const userId = "abc-123";
  assertEquals(
    validateR2ObjectKey(`staging/${userId}/photo.webp`, userId),
    null,
  );
});

Deno.test("IDOR guard - key belonging to different user is rejected", () => {
  assertEquals(
    validateR2ObjectKey("staging/other-user/photo.webp", "abc-123"),
    "wrong_user",
  );
});

Deno.test("IDOR guard - path traversal is rejected", () => {
  assertEquals(
    validateR2ObjectKey("staging/abc-123/../../etc/passwd", "abc-123"),
    "path_traversal",
  );
});

// ---------------------------------------------------------------------------
// Audio staging budget guards
// ---------------------------------------------------------------------------

Deno.test("audio staging budget - two R2 clips are accepted", () => {
  assertEquals(
    validateAudioPayloadShape([
      "staging/abc-123/one.wav",
      "staging/abc-123/two.wav",
    ], []),
    null,
  );
});

Deno.test("audio staging budget - mixed R2 and inline clips over cap are rejected before decode", () => {
  assertEquals(
    validateAudioPayloadShape([
      "staging/abc-123/one.wav",
      "staging/abc-123/two.wav",
    ], ["ZmFrZQ=="]),
    413,
  );
});

Deno.test("audio staging budget - oversized inline base64 is rejected before decode", () => {
  assertEquals(
    validateAudioPayloadShape([], [
      "A".repeat(MEDIA_BUDGETS.maxAudioBase64Chars + 1),
    ]),
    413,
  );
});

// ---------------------------------------------------------------------------
// Telemetry normalization
// ---------------------------------------------------------------------------

Deno.test("telemetry normalization accepts the active camelCase Swift payload", () => {
  const normalized = normalizeTelemetry({
    gpsLatitude: 37.7749,
    gpsLongitude: -122.4194,
    gpsElevation: 12.5,
    semanticLocation: "Zilker Park",
    weatherCondition: "Partly Cloudy",
    weatherTemperatureF: 68,
    deviceLocale: "en",
    deviceTimeZone: "America/Chicago",
    deviceRegion: "US",
    currentMonth: 4,
    timeOfDay: "10:30 AM",
    depthScaleText: "1.3 meters",
    zoomFactor: 2.0,
    estimated_size_cm: 11.5,
  });

  assertEquals(normalized.gpsLatitude, 37.7749);
  assertEquals(normalized.gpsLongitude, -122.4194);
  assertEquals(normalized.semanticLocation, "Zilker Park");
  assertEquals(normalized.weatherCondition, "Partly Cloudy");
  assertEquals(normalized.currentMonth, 4);
  assertEquals(normalized.depthScaleText, "1.3 meters");
  assertEquals(normalized.zoomFactor, 2.0);
  assertEquals(normalized.estimatedSizeCm, 11.5);
});

Deno.test("telemetry normalization coerces legacy numeric month strings", () => {
  const normalized = normalizeTelemetry({
    current_month: "04",
  });

  assertEquals(normalized.currentMonth, 4);
});

Deno.test("telemetry normalization drops invalid month strings", () => {
  const normalized = normalizeTelemetry({
    currentMonth: "April",
  });

  assertEquals(normalized.currentMonth, null);
});

Deno.test("telemetry normalization still accepts legacy snake_case aliases", () => {
  const normalized = normalizeTelemetry({
    gps_latitude: 10,
    gps_longitude: 20,
    semantic_location: "Legacy Field",
    weather_condition: "Sunny",
    current_month: "7",
    time_of_day: "7:00 AM",
    depth_scale_text: "0.7 meters",
    estimated_size_cm: 4.2,
  });

  assertEquals(normalized.gpsLatitude, 10);
  assertEquals(normalized.gpsLongitude, 20);
  assertEquals(normalized.semanticLocation, "Legacy Field");
  assertEquals(normalized.weatherCondition, "Sunny");
  assertEquals(normalized.currentMonth, 7);
  assertEquals(normalized.timeOfDay, "7:00 AM");
  assertEquals(normalized.depthScaleText, "0.7 meters");
  assertEquals(normalized.estimatedSizeCm, 4.2);
});

Deno.test("visual media telemetry marks image-only scans", () => {
  const telemetry = resolveVisualMediaTelemetry(2, null, 0);

  assertEquals(telemetry.mediaType, "image");
  assertEquals(telemetry.hasImage, true);
  assertEquals(telemetry.hasVideo, false);
  assertEquals(telemetry.imageCount, 2);
  assertEquals(telemetry.declaredVideoFrameCount, 0);
  assertEquals(telemetry.videoInferenceFrameCount, 0);
});

Deno.test("visual media telemetry attributes sampled frames to video scans", () => {
  const telemetry = resolveVisualMediaTelemetry(3, 3, 1);

  assertEquals(telemetry.mediaType, "video");
  assertEquals(telemetry.hasImage, false);
  assertEquals(telemetry.hasVideo, true);
  assertEquals(telemetry.imageCount, 0);
  assertEquals(telemetry.videoClipCount, 1);
  assertEquals(telemetry.declaredVideoFrameCount, 3);
  assertEquals(telemetry.videoInferenceFrameCount, 3);
});

Deno.test("visual media telemetry preserves still image count for mixed image and video scans", () => {
  const telemetry = resolveVisualMediaTelemetry(5, 3, 1);

  assertEquals(telemetry.mediaType, "image_video");
  assertEquals(telemetry.hasImage, true);
  assertEquals(telemetry.hasVideo, true);
  assertEquals(telemetry.imageCount, 2);
  assertEquals(telemetry.videoInferenceFrameCount, 3);
});

Deno.test("visual media telemetry uses explicit mixed image and video descriptors", () => {
  const descriptors = normalizeVisualMediaItems([
    { kind: "image", sourceIndex: 0 },
    { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
    { kind: "video_frame", clipIndex: 0, frameIndex: 1 },
  ], 3);
  const telemetry = resolveVisualMediaTelemetry(3, 3, 1, descriptors);

  assertEquals(telemetry.mediaType, "image_video");
  assertEquals(telemetry.hasImage, true);
  assertEquals(telemetry.hasVideo, true);
  assertEquals(telemetry.imageCount, 1);
  assertEquals(telemetry.videoInferenceFrameCount, 2);
});

Deno.test("visual media prompt labels still photos and sampled video frames", () => {
  const descriptors = normalizeVisualMediaItems([
    { kind: "image", sourceIndex: 0 },
    { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
    { kind: "video_frame", clipIndex: 0, frameIndex: 1 },
  ], 3);
  const prompt = buildVisualMediaPrompt(descriptors, true, 3);

  assert(prompt);
  assert(prompt.includes("Visual input 1: still photo 1"));
  assert(prompt.includes("Visual input 2: sampled video frame 1"));
  assert(prompt.includes("Visual input 3: sampled video frame 2"));
  assert(prompt.includes("This scan includes a short user-recorded video"));
  assert(!prompt.includes("The following images"));
  assert(!prompt.includes("images provided"));
});

Deno.test("visual media prompt describes video audio as accompanying audio", () => {
  const descriptors = normalizeVisualMediaItems([
    { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
    { kind: "video_frame", clipIndex: 0, frameIndex: 1 },
  ], 2);
  const audioDescriptors = normalizeAudioMediaItems([
    { kind: "video_audio", clipIndex: 0 },
  ], 1);
  const hasVideoAudio = audioDescriptors.some((item) =>
    item.kind === "video_audio"
  );
  const prompt = buildVisualMediaPrompt(descriptors, true, 2, hasVideoAudio);

  assert(prompt);
  assert(prompt.includes("sampled visual frames and accompanying audio"));
  assert(prompt.includes("evidence from that video"));
  assert(!prompt.includes("The following images"));
});

Deno.test("visual media prompt keeps still-photo language for still photos", () => {
  const descriptors = normalizeVisualMediaItems([
    { kind: "image", sourceIndex: 0 },
    { kind: "image", sourceIndex: 1 },
  ], 2);
  const prompt = buildVisualMediaPrompt(descriptors, false, 2);

  assert(prompt);
  assert(prompt.includes("ordered still photos"));
  assert(prompt.includes("Visual input 1: still photo 1"));
  assert(!prompt.includes("video scan"));
});

Deno.test("visual media prompt adds accepted still-photo focus context", () => {
  const descriptors = normalizeVisualMediaItems([{
    kind: "image",
    sourceIndex: 0,
    focusRegion: {
      x: 0.125,
      y: 0.25,
      width: 0.5,
      height: 0.4,
      source: "vision_objectness",
    },
  }], 1);
  const prompt = buildVisualMediaPrompt(descriptors, false, 1);

  assert(prompt?.includes("top-left-normalized bounds"));
  assert(prompt?.includes("x=0.1250"));
  assert(prompt?.includes("environmental context"));
});

Deno.test("visual media normalization strips malformed and video focus regions", () => {
  const descriptors = normalizeVisualMediaItems([
    {
      kind: "image",
      sourceIndex: 0,
      focusRegion: {
        x: 0.8,
        y: 0.1,
        width: 0.4,
        height: 0.4,
        source: "vision_objectness",
      },
    },
    {
      kind: "video_frame",
      clipIndex: 0,
      frameIndex: 0,
      focusRegion: {
        x: 0.1,
        y: 0.1,
        width: 0.4,
        height: 0.4,
        source: "vision_objectness",
      },
    },
  ], 2);

  assertEquals(descriptors[0].focusRegion, undefined);
  assertEquals(descriptors[1].focusRegion, undefined);
});

// ---------------------------------------------------------------------------
// Observation context merging
// ---------------------------------------------------------------------------

Deno.test("observation contexts use freeText from the active Swift model", () => {
  assertEquals(
    mergeObservationContexts([
      { freeText: "Saw it perched nearby" },
      { freeText: "Heard a short trill" },
    ]),
    ["Saw it perched nearby", "Heard a short trill"],
  );
});

Deno.test("observation contexts still accept legacy free_text aliases", () => {
  assertEquals(
    mergeObservationContexts([
      { free_text: "Legacy note one" },
      { free_text: "Legacy note two" },
    ]),
    ["Legacy note one", "Legacy note two"],
  );
});

Deno.test("observation context merge drops empty entries", () => {
  assertEquals(
    mergeObservationContexts([
      { freeText: "  " },
      { free_text: "" },
      { freeText: "usable" },
    ]),
    ["usable"],
  );
});

// ---------------------------------------------------------------------------
// GPS sanitization
// ---------------------------------------------------------------------------

Deno.test("GPS - valid coordinates pass through", () => {
  assertEquals(safeGpsLat(51.5074), 51.5074);
  assertEquals(safeGpsLon(-0.1278), -0.1278);
});

Deno.test("GPS - boundary values are valid", () => {
  assertEquals(safeGpsLat(90), 90);
  assertEquals(safeGpsLat(-90), -90);
  assertEquals(safeGpsLon(180), 180);
  assertEquals(safeGpsLon(-180), -180);
});

Deno.test("GPS - out-of-range values sanitize to null", () => {
  assertEquals(safeGpsLat(91), null);
  assertEquals(safeGpsLon(-181), null);
});

Deno.test("GPS - non-finite values sanitize to null", () => {
  assertEquals(safeGpsLat(NaN), null);
  assertEquals(safeGpsLon(Infinity), null);
});

// ---------------------------------------------------------------------------
// Scan ID passthrough
// ---------------------------------------------------------------------------

Deno.test("scanId - valid client_scan_id is preserved", () => {
  assertEquals(resolveGeneratedScanId("client-scan-abc"), "client-scan-abc");
});

Deno.test("scanId - empty string falls back to a UUID", () => {
  const result = resolveGeneratedScanId("");
  assert(result.length > 0);
});

// ---------------------------------------------------------------------------
// Candidate and LLM output hardening
// ---------------------------------------------------------------------------

Deno.test("candidates are sanitized and capped at five", () => {
  const candidates = sanitizeCandidates([
    { scientific_name: "cf. Danaus plexippus", confidence_score: 0.8 },
    { scientific_name: "Rosa canina L." },
    { scientific_name: "Pinus ponderosa" },
    { scientific_name: "Acer Palmatum" },
    { scientific_name: "Boletus edulis var. Edulis" },
    { scientific_name: "Should be dropped" },
  ]);

  assertEquals(candidates.length, 5);
  assertEquals(candidates[0].scientific_name, "Danaus plexippus");
  assertEquals(candidates[1].scientific_name, "Rosa canina");
  assertEquals(candidates[3].scientific_name, "Acer palmatum");
  assertEquals(candidates[4].scientific_name, "Boletus edulis var. edulis");
});

Deno.test("candidates are stripped when confidence is at or above the diagnostic threshold", () => {
  const candidates = [{ scientific_name: "Danaus plexippus" }];
  assertEquals(resolveReturnedCandidates(candidates, 0.99, 0.99), null);
  assertEquals(resolveReturnedCandidates(candidates, 0.995, 0.99), null);
});

Deno.test("candidates remain when confidence is below the diagnostic threshold", () => {
  const candidates = [{ scientific_name: "Danaus plexippus" }];
  assertEquals(
    resolveReturnedCandidates(candidates, 0.88, 0.99),
    candidates,
  );
});

Deno.test("ai_reasoning is clamped to 2000 characters", () => {
  assertEquals(sanitizeReasoning("x".repeat(2500)).length, 2000);
  assertEquals(sanitizeReasoning("ok"), "ok");
});

Deno.test("individual_count is bounded to positive finite integers", () => {
  assertEquals(sanitizeCount(12), 12);
  assertEquals(sanitizeCount(12.7), 13);
  assertEquals(sanitizeCount(100000), 99999);
  assertEquals(sanitizeCount(0), undefined);
  assertEquals(sanitizeCount(-4), undefined);
  assertEquals(sanitizeCount(NaN), undefined);
});

Deno.test("life_stage falls back to unknown for invalid enum values", () => {
  assertEquals(sanitizeLifeStage("adult"), "adult");
  assertEquals(sanitizeLifeStage("fledgling"), "unknown");
  assertEquals(sanitizeLifeStage(undefined), "unknown");
});

Deno.test("reproductive_condition falls back to not_applicable for invalid enum values", () => {
  assertEquals(sanitizeReproductiveCondition("flowering"), "flowering");
  assertEquals(
    sanitizeReproductiveCondition("brooding"),
    "not_applicable",
  );
  assertEquals(
    sanitizeReproductiveCondition(undefined),
    "not_applicable",
  );
});

Deno.test("sex falls back to cannot_determine for invalid enum values", () => {
  assertEquals(sanitizeSex("female"), "female");
  assertEquals(sanitizeSex("male"), "male");
  assertEquals(sanitizeSex("worker"), "cannot_determine");
  assertEquals(sanitizeSex(undefined), "cannot_determine");
});

Deno.test("latency work preserves the scoped Gemini model and generation configuration", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertEquals(
    source.match(/_genAI\.models\.generateContent\(/g)?.length,
    1,
  );
  for (
    const fragment of [
      "const targetModel = quotaLease.reservation.model;",
      "await quotaLease.commit();",
      "model: targetModel",
      "temperature: 0.1",
      "seed: 42",
      "maxOutputTokens: 8192",
      "? { thinkingBudget: 5000 }\n          : undefined",
      'responseMimeType: "application/json"',
      "responseSchema: getMerianResponseSchema(diagnosticTrigger)",
    ]
  ) {
    assert(source.includes(fragment), `missing Gemini invariant: ${fragment}`);
  }
});

Deno.test("cache-miss external enrichment begins inside background ingestion", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const backgroundStart = source.indexOf(
    "const runBackgroundIngestion = async () =>",
  );
  const primaryExternalFetch = source.indexOf(
    "externalData = await fetchExternalEnrichment",
  );
  assert(backgroundStart >= 0);
  assert(primaryExternalFetch > backgroundStart);
});

Deno.test("latency telemetry is privacy-safe and keeps the Gemini boundary exact", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const latencyStart = source.indexOf('event: "multimodal/latency"');
  const latencyEnd = source.indexOf("}));", latencyStart);
  assert(latencyStart >= 0 && latencyEnd > latencyStart);
  const latencyBlock = source.slice(latencyStart, latencyEnd);
  assert(!latencyBlock.includes("scan_id"));
  for (
    const fragment of [
      "tier: userTier",
      "model: targetModel",
      "image_count: mediaTelemetry.imageCount",
      "payload_bytes: payloadBytes",
      "edge_region: edgeRegion",
      "constrained_network: constrainedNetwork",
      "auth_ms: Math.round(authDurationMs)",
    ]
  ) {
    assert(latencyBlock.includes(fragment), `missing latency tag: ${fragment}`);
  }

  const generationCall = source.indexOf("await _genAI.models.generateContent");
  const geminiStop = source.indexOf(
    "geminiLatencyMs = Date.now() - geminiStart;",
    generationCall,
  );
  const responseExtraction = source.indexOf(
    "finishReason = result.candidates",
    generationCall,
  );
  assert(generationCall >= 0);
  assert(geminiStop > generationCall);
  assert(geminiStop < responseExtraction);
});
