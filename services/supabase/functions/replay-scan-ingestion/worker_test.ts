import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import { buildReplayIdentifyPayload, replayScanIngestion } from "./worker.ts";
import type { ReplayableScanIngestionRow, ReplayScanRow } from "./db.ts";

function replayRow(
  overrides: Partial<ReplayableScanIngestionRow> = {},
): ReplayableScanIngestionRow {
  return {
    scan_id: "scan-1",
    user_id: "user-1",
    endpoint: "identify-multimodal",
    status: "retrying",
    stage: "server_replay_claimed",
    attempt_count: 2,
    media_counts: {
      image_count: 0,
      audio_count: 1,
      video_count: 1,
      required_video_count: 1,
      video_frame_count: 5,
    },
    media_object_keys: {},
    upload_session_ids: [],
    manifest_checksum: "manifest",
    payload_checksum: "payload",
    replay_attempt_count: 1,
    request_payload: {
      schemaVersion: 1,
      clientScanId: "scan-1",
      endpoint: "identify-multimodal",
      media: {
        r2ObjectKeys: [
          "staging/user-1/frame-1.webp",
          "staging/user-1/frame-2.webp",
        ],
        audioR2ObjectKeys: ["staging/user-1/audio.wav"],
        videoR2ObjectKeys: ["staging/user-1/playback.mp4"],
        videoFrameCount: 2,
        visualMediaItems: [
          { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
          { kind: "video_frame", clipIndex: 0, frameIndex: 1 },
        ],
        audioMediaItems: [{ kind: "video_audio", clipIndex: 0 }],
        mimeType: "image/webp",
      },
      telemetry: {
        timestamp: "2026-07-05T03:00:00.000Z",
        gpsLatitude: 30.1,
        gpsLongitude: -97.7,
        semanticLocation: "Austin, TX",
        geoprivacy: "open",
      },
      observationContexts: [
        { freeText: "On the porch", addedAt: "2026-07-05T02:59:00.000Z" },
      ],
      preferredGoal: {
        userFieldTripId: "00000000-0000-4000-8000-000000000001",
        itemId: "00000000-0000-4000-8000-000000000002",
      },
    },
    ...overrides,
  };
}

Deno.test("buildReplayIdentifyPayload reconstructs top-level multimodal request without raw media", () => {
  const payload = buildReplayIdentifyPayload(replayRow());

  assertObjectMatch(payload, {
    user_id: "user-1",
    client_scan_id: "scan-1",
    r2ObjectKeys: [
      "staging/user-1/frame-1.webp",
      "staging/user-1/frame-2.webp",
    ],
    audioR2ObjectKeys: ["staging/user-1/audio.wav"],
    videoR2ObjectKeys: ["staging/user-1/playback.mp4"],
    videoFrameCount: 2,
    mimeType: "image/webp",
    gpsLatitude: 30.1,
    gpsLongitude: -97.7,
    semanticLocation: "Austin, TX",
    geoprivacy: "open",
    preferred_goal: {
      user_field_trip_id: "00000000-0000-4000-8000-000000000001",
      item_id: "00000000-0000-4000-8000-000000000002",
    },
  });
  assertEquals("imageBase64s" in payload, false);
  assertEquals("audioBase64s" in payload, false);
  assertEquals(Array.isArray(payload.visualMediaItems), true);
  assertEquals(Array.isArray(payload.audioMediaItems), true);
  assertEquals(Array.isArray(payload.observation_contexts), true);
});

Deno.test("replayScanIngestion dispatches staged rows through identify", async () => {
  const invoked: unknown[] = [];
  const completed: unknown[] = [];
  const failures: unknown[] = [];

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: "service-role",
      awaitInvocations: true,
    },
    {
      claimJobs: () => Promise.resolve([replayRow()]),
      fetchScans: () => Promise.resolve([]),
      markComplete: (input) => {
        completed.push(input);
        return Promise.resolve();
      },
      markFailure: (input) => {
        failures.push(input);
        return Promise.resolve();
      },
      invokeIdentify: (input) => {
        invoked.push(input);
        return Promise.resolve();
      },
    },
  );

  assertEquals(result.claimed, 1);
  assertEquals(result.dispatched, 1);
  assertEquals(result.failedDispatches, 0);
  assertEquals(completed.length, 0);
  assertEquals(failures.length, 0);
  assertEquals(invoked.length, 1);
});

Deno.test("replayScanIngestion marks already-complete scan rows complete without invoking identify", async () => {
  const invoked: unknown[] = [];
  const completed: unknown[] = [];
  const scan: ReplayScanRow = {
    id: "scan-1",
    user_id: "user-1",
    video_storage_urls: ["https://media.merian.app/public/video.mp4"],
    captured_media: [{
      video: {
        _0: {
          video: {
            storage: "remoteURL",
            path: "https://media.merian.app/public/video.mp4",
          },
        },
      },
    }],
  };

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: "service-role",
      awaitInvocations: true,
    },
    {
      claimJobs: () => Promise.resolve([replayRow()]),
      fetchScans: () => Promise.resolve([scan]),
      markComplete: (input) => {
        completed.push(input);
        return Promise.resolve();
      },
      markFailure: () => Promise.resolve(),
      invokeIdentify: (input) => {
        invoked.push(input);
        return Promise.resolve();
      },
    },
  );

  assertEquals(result.claimed, 1);
  assertEquals(result.dispatched, 0);
  assertEquals(result.completedExisting, 1);
  assertEquals(completed.length, 1);
  assertEquals(invoked.length, 0);
});

Deno.test("replayScanIngestion leaves existing incomplete video scans for repair", async () => {
  const failures: unknown[] = [];
  const scan: ReplayScanRow = {
    id: "scan-1",
    user_id: "user-1",
    video_storage_urls: [],
    captured_media: [],
  };

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: "service-role",
      awaitInvocations: true,
    },
    {
      claimJobs: () => Promise.resolve([replayRow()]),
      fetchScans: () => Promise.resolve([scan]),
      markComplete: () => Promise.resolve(),
      markFailure: (input) => {
        failures.push(input);
        return Promise.resolve();
      },
      invokeIdentify: () => Promise.resolve(),
    },
  );

  assertEquals(result.claimed, 1);
  assertEquals(result.dispatched, 0);
  assertEquals(result.skippedExistingIncomplete, 1);
  assertEquals(failures.length, 1);
});
