import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { buildScanIngestionIntent } from "./scanIngestionIntents.ts";

Deno.test("buildScanIngestionIntent stores staged media intent without raw inline bytes", async () => {
  const intent = await buildScanIngestionIntent({
    scanId: "scan-1",
    payload: {
      user_id: "spoofed-user",
      client_scan_id: "scan-1",
      imageBase64s: ["raw-image"],
      audioBase64s: ["raw-audio"],
      r2ObjectKeys: ["staging/user-1/frame.webp"],
      audioR2ObjectKeys: ["staging/user-1/audio.wav"],
      videoR2ObjectKeys: ["staging/user-1/video.mp4"],
      videoFrameCount: 5,
      visualMediaItems: [
        { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
      ],
      audioMediaItems: [{ kind: "video_audio", clipIndex: 0 }],
      observation_contexts: [{
        freeText: "Near a pond",
        addedAt: "2026-07-05T12:00:00.000Z",
      }],
      gpsLatitude: 30.25,
      gpsLongitude: -97.75,
      weatherCondition: "Clear",
      currentMonth: 7,
      mimeType: "image/webp",
    },
    mediaCounts: {
      image_count: 1,
      audio_count: 1,
      video_count: 1,
      required_video_count: 1,
      video_frame_count: 5,
      video_inference_frame_count: 5,
      has_description: true,
    },
    mediaObjectKeys: {
      image: ["staging/user-1/frame.webp"],
      audio: ["staging/user-1/audio.wav"],
      video: ["staging/user-1/video.mp4"],
    },
    uploadSessionIds: ["session-b", "session-a"],
    manifestChecksum: "abc123",
  });

  assertEquals(intent.resumable, false);
  assertEquals(intent.inlineMediaRedacted, true);
  assertEquals(intent.redactedMediaCounts, {
    image_base64_count: 1,
    audio_base64_count: 1,
  });
  assertEquals(intent.payloadChecksum.length, 64);
  assertEquals(JSON.stringify(intent.payload).includes("raw-image"), false);
  assertEquals(JSON.stringify(intent.payload).includes("raw-audio"), false);
  assertEquals(intent.payload.media, {
    r2ObjectKeys: ["staging/user-1/frame.webp"],
    audioR2ObjectKeys: ["staging/user-1/audio.wav"],
    videoR2ObjectKeys: ["staging/user-1/video.mp4"],
    videoFrameCount: 5,
    visualMediaItems: [{
      kind: "video_frame",
      clipIndex: 0,
      frameIndex: 0,
    }],
    audioMediaItems: [{ kind: "video_audio", clipIndex: 0 }],
    mimeType: "image/webp",
  });
});

Deno.test("buildScanIngestionIntent is stable for staged-only retry payloads", async () => {
  const base = {
    scanId: "scan-1",
    mediaCounts: {
      image_count: 0,
      audio_count: 0,
      video_count: 0,
      required_video_count: 0,
      video_frame_count: 0,
      has_description: true,
    },
    mediaObjectKeys: {
      image: [],
      audio: [],
      video: [],
    },
    uploadSessionIds: [" session-b ", "session-a", "session-a"],
    manifestChecksum: "manifest",
  };
  const lhs = await buildScanIngestionIntent({
    ...base,
    payload: {
      user_id: "user-1",
      client_scan_id: "scan-1",
      observation_contexts: [{ free_text: "  A text-only note " }],
      current_month: "7",
    },
    normalizedTelemetry: { currentMonth: 7 },
  });
  const rhs = await buildScanIngestionIntent({
    ...base,
    payload: {
      user_id: "user-1",
      client_scan_id: "scan-1",
      observation_contexts: [{ freeText: "A text-only note" }],
      currentMonth: 7,
    },
    normalizedTelemetry: { currentMonth: 7 },
  });

  assertEquals(lhs.resumable, true);
  assertEquals(lhs.inlineMediaRedacted, false);
  assertEquals(lhs.payloadChecksum, rhs.payloadChecksum);
  assertEquals(lhs.payload.uploadSessionIds, ["session-a", "session-b"]);
});
