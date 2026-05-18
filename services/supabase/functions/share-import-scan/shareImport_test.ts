import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildIdentifyMultimodalPayload,
  jobStatusForIdentifyResponse,
  queuedJobRow,
  validateShareImportRequest,
} from "./shareImport.ts";

Deno.test("share import validates exactly one owned image key", () => {
  const result = validateShareImportRequest({
    scan_id: "11111111-1111-4111-8111-111111111111",
    r2ObjectKey: "staging/user-123/photo.webp",
    mimeType: "image/webp",
  }, "user-123");

  assertExists(result.value);
  assertEquals(result.value.scanId, "11111111-1111-4111-8111-111111111111");
  assertEquals(result.value.r2ObjectKey, "staging/user-123/photo.webp");
});

Deno.test("share import rejects non-owned staging keys", () => {
  const result = validateShareImportRequest({
    r2ObjectKey: "staging/other-user/photo.webp",
    mimeType: "image/webp",
  }, "user-123");

  assertEquals(result.error?.status, 403);
});

Deno.test("share import rejects multi-image input", () => {
  const result = validateShareImportRequest({
    r2ObjectKeys: [
      "staging/user-123/one.webp",
      "staging/user-123/two.webp",
    ],
    mimeType: "image/webp",
  }, "user-123");

  assertEquals(result.error?.status, 400);
});

Deno.test("share import builds identify-multimodal payload", () => {
  const validated = validateShareImportRequest({
    scan_id: "11111111-1111-4111-8111-111111111111",
    r2ObjectKey: "staging/user-123/photo.webp",
    mimeType: "image/webp",
    timestamp: "2026-05-18T12:30:00.000Z",
    gpsLatitude: 30.1,
    gpsLongitude: -97.7,
  }, "user-123");

  const payload = buildIdentifyMultimodalPayload(validated.value!, "user-123");
  assertEquals(payload.user_id, "user-123");
  assertEquals(payload.client_scan_id, "11111111-1111-4111-8111-111111111111");
  assertEquals(payload.r2ObjectKeys, ["staging/user-123/photo.webp"]);
  assertEquals(payload.currentMonth, 5);
});

Deno.test("share import queued job row and failure state are explicit", () => {
  const validated = validateShareImportRequest({
    scan_id: "11111111-1111-4111-8111-111111111111",
    r2ObjectKey: "staging/user-123/photo.webp",
    mimeType: "image/jpeg",
  }, "user-123");

  assertEquals(queuedJobRow(validated.value!, "user-123"), {
    scan_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-123",
    status: "queued",
    r2_object_key: "staging/user-123/photo.webp",
    mime_type: "image/jpeg",
  });

  const failure = jobStatusForIdentifyResponse(500, "server exploded");
  assertEquals(failure.status, "failed");
  assertEquals(failure.response_status, 500);
});
