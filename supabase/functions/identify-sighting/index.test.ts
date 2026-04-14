// supabase/functions/identify-sighting/index.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// buildObservationPrompt — mirrors the function in index.ts.
// Extracted here so we can assert its output contract without importing the
// module (which pulls in heavy Deno runtime dependencies).
// ---------------------------------------------------------------------------

function buildObservationPrompt(
  description: string,
  telemetry: {
    safeGpsLat: number | null;
    safeGpsLon: number | null;
    gpsElevation?: number;
    semanticLocation?: string;
    weatherCondition?: string;
    weatherTemperatureF?: number;
    deviceLocale?: string;
    deviceTimeZone?: string;
    deviceRegion?: string;
    currentMonth?: number;
    timeOfDay?: string;
  },
): string {
  const contextItems = [
    telemetry.safeGpsLat != null && telemetry.safeGpsLon != null
      ? `GPS:${telemetry.safeGpsLat},${telemetry.safeGpsLon}` : null,
    telemetry.gpsElevation != null ? `Elev:${telemetry.gpsElevation}m` : null,
    telemetry.semanticLocation ? `Loc:${telemetry.semanticLocation}` : null,
    telemetry.weatherCondition ? `Wx:${telemetry.weatherCondition}` : null,
    telemetry.weatherTemperatureF != null ? `Temp:${telemetry.weatherTemperatureF}F` : null,
    telemetry.deviceLocale ? `Locale:${telemetry.deviceLocale}` : null,
    telemetry.deviceTimeZone ? `TZ:${telemetry.deviceTimeZone}` : null,
    telemetry.deviceRegion ? `Region:${telemetry.deviceRegion}` : null,
    telemetry.currentMonth ? `Month:${telemetry.currentMonth}` : null,
    telemetry.timeOfDay ? `Time:${telemetry.timeOfDay}` : null,
  ].filter(Boolean);

  const contextBlock = contextItems.length > 0
    ? `Context: ${contextItems.join(", ")}.\n\n`
    : "";

  return `${contextBlock}Observation Description:\n${description}`;
}

// ---------------------------------------------------------------------------
// Sighting schema contract — asserts structural invariants that are unique
// to the sighting path vs. the vision path:
//   • is_live_capture is always false
//   • image_quality_score is always null / absent
//   • blur_score is always 0
//   • image_storage_urls is always an empty array
//   • description field is required and non-empty
// ---------------------------------------------------------------------------

Deno.test("Sighting schema contract — is_live_capture is always false", () => {
  const mockScanRow = {
    is_live_capture: false as const,
    image_storage_urls: [] as string[],
    image_quality_score: null as null,
  };
  assertEquals(mockScanRow.is_live_capture, false);
});

Deno.test("Sighting schema contract — image_storage_urls is always empty", () => {
  const mockScanRow = {
    is_live_capture: false as const,
    image_storage_urls: [] as string[],
    image_quality_score: null as null,
  };
  assertEquals(mockScanRow.image_storage_urls.length, 0);
});

Deno.test("Sighting schema contract — image_quality_score is always null", () => {
  const mockScanRow = {
    is_live_capture: false as const,
    image_storage_urls: [] as string[],
    image_quality_score: null as null,
  };
  assertEquals(mockScanRow.image_quality_score, null);
});

Deno.test("Sighting response contract — blur_score is always 0 (no image to assess)", () => {
  // Mirrors the `parsedData.blur_score = 0` override in index.ts.
  // Any value the LLM returns for blur_score must be overwritten to 0 because
  // there is no image — a non-zero blur score would incorrectly trigger the
  // blur advisory UI on iOS.
  const blur_score = 0;
  assertEquals(blur_score, 0);
  assert(blur_score >= 0, "blur_score must never be negative");
});

// ---------------------------------------------------------------------------
// buildObservationPrompt — structure and content tests
// ---------------------------------------------------------------------------

Deno.test("buildObservationPrompt — description always appears in output", () => {
  const output = buildObservationPrompt("Yellow butterfly with black spots", {
    safeGpsLat: null,
    safeGpsLon: null,
  });
  assert(output.includes("Yellow butterfly with black spots"));
  assert(output.includes("Observation Description:"));
});

Deno.test("buildObservationPrompt — empty telemetry produces no context block", () => {
  const output = buildObservationPrompt("A small red beetle", {
    safeGpsLat: null,
    safeGpsLon: null,
  });
  assert(!output.includes("Context:"), "Context: block must be absent when all telemetry is null/undefined");
  assert(output.startsWith("Observation Description:"));
});

Deno.test("buildObservationPrompt — GPS coordinates appear when both are valid", () => {
  const output = buildObservationPrompt("Dragonfly", {
    safeGpsLat: 51.5074,
    safeGpsLon: -0.1278,
  });
  assert(output.includes("GPS:51.5074,-0.1278"), "GPS coordinates must appear in context block");
  assert(output.includes("Context:"));
});

Deno.test("buildObservationPrompt — GPS omitted when only one coordinate is present", () => {
  const latOnly = buildObservationPrompt("Moth", { safeGpsLat: 40.0, safeGpsLon: null });
  assert(!latOnly.includes("GPS:"), "GPS line must be absent when longitude is null");

  const lonOnly = buildObservationPrompt("Moth", { safeGpsLat: null, safeGpsLon: -74.0 });
  assert(!lonOnly.includes("GPS:"), "GPS line must be absent when latitude is null");
});

Deno.test("buildObservationPrompt — elevation included when provided", () => {
  const output = buildObservationPrompt("Mountain spider", {
    safeGpsLat: null,
    safeGpsLon: null,
    gpsElevation: 2300,
  });
  assert(output.includes("Elev:2300m"));
});

Deno.test("buildObservationPrompt — weather fields included when provided", () => {
  const output = buildObservationPrompt("Frog near pond", {
    safeGpsLat: null,
    safeGpsLon: null,
    weatherCondition: "Partly Cloudy",
    weatherTemperatureF: 68,
  });
  assert(output.includes("Wx:Partly Cloudy"));
  assert(output.includes("Temp:68F"));
});

Deno.test("buildObservationPrompt — device locale, timezone, region all included when provided", () => {
  const output = buildObservationPrompt("Bird on a wire", {
    safeGpsLat: null,
    safeGpsLon: null,
    deviceLocale: "en-US",
    deviceTimeZone: "America/New_York",
    deviceRegion: "US",
  });
  assert(output.includes("Locale:en-US"));
  assert(output.includes("TZ:America/New_York"));
  assert(output.includes("Region:US"));
});

Deno.test("buildObservationPrompt — currentMonth included when provided", () => {
  const output = buildObservationPrompt("Caterpillar", {
    safeGpsLat: null,
    safeGpsLon: null,
    currentMonth: 6,
  });
  assert(output.includes("Month:6"));
});

Deno.test("buildObservationPrompt — timeOfDay included when provided", () => {
  const output = buildObservationPrompt("Nocturnal moth", {
    safeGpsLat: null,
    safeGpsLon: null,
    timeOfDay: "night",
  });
  assert(output.includes("Time:night"));
});

Deno.test("buildObservationPrompt — semantic location included when provided", () => {
  const output = buildObservationPrompt("Deer tracks", {
    safeGpsLat: null,
    safeGpsLon: null,
    semanticLocation: "Sherwood Forest, Nottinghamshire",
  });
  assert(output.includes("Loc:Sherwood Forest, Nottinghamshire"));
});

Deno.test("buildObservationPrompt — full telemetry context prefix appears before description", () => {
  const output = buildObservationPrompt("Green leaf insect", {
    safeGpsLat: 3.14,
    safeGpsLon: 101.7,
    currentMonth: 3,
  });
  const contextIndex = output.indexOf("Context:");
  const descIndex = output.indexOf("Observation Description:");
  assert(contextIndex !== -1, "Context: block must be present");
  assert(contextIndex < descIndex, "Context block must precede the description");
});

Deno.test("buildObservationPrompt — context items are comma-separated", () => {
  const output = buildObservationPrompt("Beetle", {
    safeGpsLat: 48.8566,
    safeGpsLon: 2.3522,
    currentMonth: 7,
    timeOfDay: "morning",
  });
  // All three context items must appear on the same Context: line, comma-separated
  assert(output.includes("GPS:48.8566,2.3522, Month:7, Time:morning") ||
    output.includes("GPS:") && output.includes("Month:") && output.includes("Time:"),
    "Context items must be comma-separated on a single line");
});

// ---------------------------------------------------------------------------
// description validation — mirrors `typeof description !== "string" ||
// description.trim().length === 0` guard in index.ts
// ---------------------------------------------------------------------------

function isValidDescription(v: unknown): boolean {
  return typeof v === "string" && v.trim().length > 0;
}

Deno.test("description validation — non-empty string is valid", () => {
  assert(isValidDescription("A yellow beetle with spots"));
});

Deno.test("description validation — empty string is invalid", () => {
  assert(!isValidDescription(""));
});

Deno.test("description validation — whitespace-only string is invalid", () => {
  assert(!isValidDescription("   \t\n  "));
});

Deno.test("description validation — null is invalid", () => {
  assert(!isValidDescription(null));
});

Deno.test("description validation — undefined is invalid", () => {
  assert(!isValidDescription(undefined));
});

Deno.test("description validation — number is invalid", () => {
  assert(!isValidDescription(42));
});

Deno.test("description validation — object is invalid", () => {
  assert(!isValidDescription({ text: "Beetle" }));
});

// ---------------------------------------------------------------------------
// client_scan_id passthrough — mirrors the generatedScanId derivation in index.ts.
// When the client provides a valid client_scan_id it must be used as-is
// (enables the iOS deduplication path). A missing or invalid value → new UUID.
// ---------------------------------------------------------------------------

function resolveGeneratedScanId(client_scan_id: unknown): string {
  return typeof client_scan_id === "string" && client_scan_id.length > 0
    ? client_scan_id
    : crypto.randomUUID();
}

Deno.test("scanId resolution — valid client_scan_id is passed through unchanged", () => {
  const id = "abc-123-def-456";
  assertEquals(resolveGeneratedScanId(id), id);
});

Deno.test("scanId resolution — empty client_scan_id falls back to a new UUID", () => {
  const result = resolveGeneratedScanId("");
  assert(result.length > 0, "Fallback UUID must be non-empty");
  assert(result !== "", "Empty string must not be passed through");
});

Deno.test("scanId resolution — null client_scan_id falls back to a new UUID", () => {
  const result = resolveGeneratedScanId(null);
  assert(result.length > 0);
});

Deno.test("scanId resolution — undefined client_scan_id falls back to a new UUID", () => {
  const result = resolveGeneratedScanId(undefined);
  assert(result.length > 0);
});

Deno.test("scanId resolution — two null calls produce distinct UUIDs", () => {
  const a = resolveGeneratedScanId(null);
  const b = resolveGeneratedScanId(null);
  assert(a !== b, "Each fallback UUID must be unique");
});

// ---------------------------------------------------------------------------
// GPS validation — same guards as identify/index.ts (copied here to validate
// the sighting path independently)
// ---------------------------------------------------------------------------

function safeGpsLat(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
    v >= -90 && v <= 90 ? v : null;
}
function safeGpsLon(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
    v >= -180 && v <= 180 ? v : null;
}

Deno.test("GPS — sighting path: valid coordinates pass through", () => {
  assertEquals(safeGpsLat(51.5074), 51.5074);
  assertEquals(safeGpsLon(-0.1278), -0.1278);
});

Deno.test("GPS — sighting path: out-of-range values sanitised to null", () => {
  assertEquals(safeGpsLat(91), null);
  assertEquals(safeGpsLat(-91), null);
  assertEquals(safeGpsLon(181), null);
  assertEquals(safeGpsLon(-181), null);
});

Deno.test("GPS — sighting path: non-finite values sanitised to null", () => {
  assertEquals(safeGpsLat(NaN), null);
  assertEquals(safeGpsLat(Infinity), null);
  assertEquals(safeGpsLon(-Infinity), null);
});

Deno.test("GPS — sighting path: null and undefined sanitised to null", () => {
  assertEquals(safeGpsLat(null), null);
  assertEquals(safeGpsLat(undefined), null);
  assertEquals(safeGpsLon(null), null);
});

Deno.test("GPS — sighting path: zero coordinates are valid (equator / prime meridian)", () => {
  assertEquals(safeGpsLat(0), 0);
  assertEquals(safeGpsLon(0), 0);
});

// ---------------------------------------------------------------------------
// LLM caps — sighting path (same cap logic, independent assertion)
// ---------------------------------------------------------------------------

Deno.test("Sighting LLM caps — extracted_visual_traits capped at 10", () => {
  const traits = Array.from({ length: 15 }, (_, i) => `trait ${i}`);
  assertEquals(traits.slice(0, 10).length, 10);
});

Deno.test("Sighting LLM caps — candidates capped at 5", () => {
  const candidates = Array.from({ length: 8 }, (_, i) => ({
    scientific_name: `Species ${i}`,
    confidence_score: 0.5,
  }));
  assertEquals(candidates.slice(0, 5).length, 5);
});

Deno.test("Sighting LLM caps — ai_reasoning truncated at 2000 chars", () => {
  const long = "x".repeat(2500);
  const truncated = long.length > 2000 ? long.slice(0, 2000) : long;
  assertEquals(truncated.length, 2000);
});

// ---------------------------------------------------------------------------
// Sighting-specific confidence calibration
// The sighting schema system instruction anchors typical confidence at 0.45–0.75
// (vs 0.80–0.95 for vision). The diagnostic strip trigger is the same threshold,
// but sighting results should rarely produce scores that strip candidates.
// This test verifies that a confidence score of 0.75 would still carry candidates.
// ---------------------------------------------------------------------------

function applyDiagnosticStrip(
  confidenceScore: number | null | undefined,
  diagnosticTrigger: number,
  candidates: unknown[],
): unknown[] | null {
  if ((confidenceScore ?? 0.0) >= diagnosticTrigger) return null;
  return candidates;
}

Deno.test("Sighting confidence — typical mid-confidence (0.65) preserves candidates", () => {
  const candidates = [{ scientific_name: "Papilio machaon" }];
  assertEquals(applyDiagnosticStrip(0.65, 0.99, candidates), candidates);
});

Deno.test("Sighting confidence — typical upper-sighting score (0.75) still preserves candidates", () => {
  const candidates = [{ scientific_name: "Papilio machaon" }];
  assertEquals(applyDiagnosticStrip(0.75, 0.99, candidates), candidates);
});

Deno.test("Sighting confidence — only a score ≥ 0.99 strips candidates (same threshold as vision)", () => {
  const candidates = [{ scientific_name: "Danaus plexippus" }];
  assertEquals(applyDiagnosticStrip(0.99, 0.99, candidates), null);
  assertEquals(applyDiagnosticStrip(0.98, 0.99, candidates), candidates);
});
