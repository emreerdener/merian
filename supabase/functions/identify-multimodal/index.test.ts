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
