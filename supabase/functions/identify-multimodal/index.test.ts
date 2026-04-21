// supabase/functions/identify-multimodal/index.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// Pure helpers extracted from index.ts for isolated unit testing.
// These mirror the logic in the handler without pulling in Deno runtime deps.
// ---------------------------------------------------------------------------

// Dispatch rule — mirrors lines 146-154 in index.ts.
function resolveSystemInstruction(
  hasImages: boolean,
  hasAudio: boolean,
): "BLENDED" | "VISION" | "BIOACOUSTIC" | "DESCRIBE" {
  if (hasImages && hasAudio) return "BLENDED";
  if (hasImages) return "VISION";
  if (hasAudio) return "BIOACOUSTIC";
  return "DESCRIBE";
}

// partsArray guard — mirrors lines 185-187 in index.ts.
// partsArray always contains at least the telemetry item (length >= 1).
// Returns true when the request must be rejected (only telemetry, no media or context).
function isPayloadEmpty(partsArrayLength: number, hasObservationContexts: boolean): boolean {
  return partsArrayLength === 1 && !hasObservationContexts;
}

// R2 key IDOR + path-traversal guard — mirrors lines 101-113 in index.ts.
type R2KeyError = "path_traversal" | "wrong_user" | null;
function validateR2ObjectKey(key: string, userId: string): R2KeyError {
  if (key.includes("..")) return "path_traversal";
  if (!key.startsWith(`staging/${userId}/`)) return "wrong_user";
  return null;
}

// GPS sanitisation — mirrors lines 92-98 in index.ts.
function safeGpsLat(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
    v >= -90 && v <= 90 ? v : null;
}
function safeGpsLon(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
    v >= -180 && v <= 180 ? v : null;
}

// scanId passthrough — mirrors lines 86-89 in index.ts.
function resolveGeneratedScanId(client_scan_id: unknown): string {
  return typeof client_scan_id === "string" && client_scan_id.length > 0
    ? client_scan_id
    : crypto.randomUUID();
}

// ---------------------------------------------------------------------------
// Dispatch rule tests
// ---------------------------------------------------------------------------

Deno.test("dispatch — images + audio → BLENDED instruction", () => {
  assertEquals(resolveSystemInstruction(true, true), "BLENDED");
});

Deno.test("dispatch — images only → VISION instruction", () => {
  assertEquals(resolveSystemInstruction(true, false), "VISION");
});

Deno.test("dispatch — audio only → BIOACOUSTIC instruction", () => {
  assertEquals(resolveSystemInstruction(false, true), "BIOACOUSTIC");
});

Deno.test("dispatch — no images, no audio → DESCRIBE instruction", () => {
  assertEquals(resolveSystemInstruction(false, false), "DESCRIBE");
});

// ---------------------------------------------------------------------------
// partsArray empty-payload guard
// ---------------------------------------------------------------------------

Deno.test("payload guard — only telemetry item and no contexts → reject (400)", () => {
  // partsArray has 1 item (telemetry); no contexts → must return 400
  assert(isPayloadEmpty(1, false));
});

Deno.test("payload guard — contexts only (no images, no audio) → accept (not 400)", () => {
  // partsArray: context item + telemetry item = length 2 → condition false → DESCRIBE path
  assert(!isPayloadEmpty(2, true));
});

Deno.test("payload guard — image + telemetry → accept", () => {
  assert(!isPayloadEmpty(2, false));
});

Deno.test("payload guard — audio + telemetry → accept", () => {
  assert(!isPayloadEmpty(2, false));
});

Deno.test("payload guard — context + image + telemetry → accept", () => {
  assert(!isPayloadEmpty(3, true));
});

// ---------------------------------------------------------------------------
// R2 key IDOR + path-traversal guard
// ---------------------------------------------------------------------------

Deno.test("IDOR guard — key belonging to correct user passes", () => {
  const userId = "abc-123";
  assertEquals(validateR2ObjectKey(`staging/${userId}/photo.webp`, userId), null);
});

Deno.test("IDOR guard — key belonging to different user is rejected", () => {
  assertEquals(
    validateR2ObjectKey("staging/other-user/photo.webp", "abc-123"),
    "wrong_user",
  );
});

Deno.test("IDOR guard — path traversal sequence (..) is rejected", () => {
  assertEquals(
    validateR2ObjectKey("staging/abc-123/../other-user/secret.webp", "abc-123"),
    "path_traversal",
  );
});

Deno.test("IDOR guard — path traversal detected before ownership check", () => {
  // Even if user prefix matches, traversal must be caught first
  assertEquals(
    validateR2ObjectKey("staging/abc-123/../../etc/passwd", "abc-123"),
    "path_traversal",
  );
});

Deno.test("IDOR guard — empty key string is rejected as wrong_user", () => {
  assertEquals(validateR2ObjectKey("", "abc-123"), "wrong_user");
});

// ---------------------------------------------------------------------------
// GPS sanitisation
// ---------------------------------------------------------------------------

Deno.test("GPS — valid coordinates pass through", () => {
  assertEquals(safeGpsLat(51.5074), 51.5074);
  assertEquals(safeGpsLon(-0.1278), -0.1278);
});

Deno.test("GPS — boundary values are valid (±90 lat, ±180 lon)", () => {
  assertEquals(safeGpsLat(90), 90);
  assertEquals(safeGpsLat(-90), -90);
  assertEquals(safeGpsLon(180), 180);
  assertEquals(safeGpsLon(-180), -180);
});

Deno.test("GPS — out-of-range values sanitised to null", () => {
  assertEquals(safeGpsLat(91), null);
  assertEquals(safeGpsLat(-91), null);
  assertEquals(safeGpsLon(181), null);
  assertEquals(safeGpsLon(-181), null);
});

Deno.test("GPS — non-finite values sanitised to null", () => {
  assertEquals(safeGpsLat(NaN), null);
  assertEquals(safeGpsLat(Infinity), null);
  assertEquals(safeGpsLon(-Infinity), null);
});

Deno.test("GPS — null and undefined sanitised to null", () => {
  assertEquals(safeGpsLat(null), null);
  assertEquals(safeGpsLat(undefined), null);
  assertEquals(safeGpsLon(null), null);
});

Deno.test("GPS — zero is valid (equator / prime meridian)", () => {
  assertEquals(safeGpsLat(0), 0);
  assertEquals(safeGpsLon(0), 0);
});

// ---------------------------------------------------------------------------
// scanId passthrough
// ---------------------------------------------------------------------------

Deno.test("scanId — valid client_scan_id is passed through unchanged", () => {
  const id = "client-scan-abc-123";
  assertEquals(resolveGeneratedScanId(id), id);
});

Deno.test("scanId — empty string falls back to a new UUID", () => {
  const result = resolveGeneratedScanId("");
  assert(result.length > 0);
  assert(result !== "");
});

Deno.test("scanId — null falls back to a new UUID", () => {
  const result = resolveGeneratedScanId(null);
  assert(result.length > 0);
});

Deno.test("scanId — undefined falls back to a new UUID", () => {
  const result = resolveGeneratedScanId(undefined);
  assert(result.length > 0);
});

Deno.test("scanId — two null calls produce distinct UUIDs", () => {
  const a = resolveGeneratedScanId(null);
  const b = resolveGeneratedScanId(null);
  assert(a !== b, "Each fallback UUID must be unique");
});
