import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { buildCompatibilityScanIngestionIntent } from "./scanIngestionCompatibility.ts";

Deno.test("buildCompatibilityScanIngestionIntent maps staged legacy images to multimodal replay payload", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify",
    imageKeys: [" staging/user-1/image.webp ", "staging/user-1/image.webp"],
    description: "White bands on leaf underside.",
    mimeType: "image/webp",
    telemetry: {
      timestamp: "2026-07-05T03:00:00.000Z",
      gpsLatitude: 30.1,
      gpsLongitude: -97.7,
      currentMonth: 7,
    },
    uploadSessionIds: ["session-b", " session-a ", "session-a"],
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.inlineMediaRedacted, false);
  assertEquals(intent.mediaCounts, {
    image_count: 1,
    audio_count: 0,
    video_count: 0,
    required_video_count: 0,
    video_frame_count: 0,
    video_inference_frame_count: 0,
    has_description: true,
  });
  assertEquals(intent.mediaObjectKeys, {
    image: ["staging/user-1/image.webp"],
    audio: [],
    video: [],
  });
  assertEquals(intent.uploadSessionIds, ["session-a", "session-b"]);
  assertEquals(intent.payloadChecksum.length, 64);
  assertEquals(intent.requestPayload.endpoint, "identify-multimodal");
  assertEquals(intent.requestPayload.compatibilityEndpoint, "identify");
  assertEquals(intent.requestPayload.media, {
    r2ObjectKeys: ["staging/user-1/image.webp"],
    audioR2ObjectKeys: [],
    videoR2ObjectKeys: [],
    videoFrameCount: 0,
    visualMediaItems: [],
    audioMediaItems: [],
    mimeType: "image/webp",
  });
  assertEquals(intent.requestPayload.observationContexts, [
    { freeText: "White bands on leaf underside." },
  ]);
});

Deno.test("buildCompatibilityScanIngestionIntent redacts inline media and blocks server replay", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify",
    inlineImageCount: 2,
    inlineAudioCount: 1,
    description: "Nearby creek.",
  });

  assertEquals(intent.resumable, false);
  assertEquals(intent.inlineMediaRedacted, true);
  assertEquals(intent.redactedMediaCounts, {
    image_base64_count: 2,
    audio_base64_count: 1,
  });
  assertEquals(
    JSON.stringify(intent.requestPayload).includes("raw-image"),
    false,
  );
  assertEquals(
    JSON.stringify(intent.requestPayload).includes("raw-audio"),
    false,
  );
});

Deno.test("buildCompatibilityScanIngestionIntent keeps describe-only rows replayable", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "identify-describe",
    description: "Small brown mushroom growing from a lawn after rain.",
    telemetry: { semanticLocation: "Austin, TX", currentMonth: 7 },
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.mediaCounts.has_description, true);
  assertEquals(intent.mediaCounts.image_count, 0);
  assertEquals(intent.mediaCounts.audio_count, 0);
  assertEquals(intent.requestPayload.observationContexts, [
    { freeText: "Small brown mushroom growing from a lawn after rain." },
  ]);
});

Deno.test("buildCompatibilityScanIngestionIntent keeps staged legacy audio replayable", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: "scan-1",
    endpoint: "audio-spec",
    audioKeys: ["staging/user-1/audio.wav"],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
  });

  assertEquals(intent.resumable, true);
  assertEquals(intent.mediaCounts.audio_count, 1);
  assertEquals(intent.requestPayload.media, {
    r2ObjectKeys: [],
    audioR2ObjectKeys: ["staging/user-1/audio.wav"],
    videoR2ObjectKeys: [],
    videoFrameCount: 0,
    visualMediaItems: [],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
  });
});
