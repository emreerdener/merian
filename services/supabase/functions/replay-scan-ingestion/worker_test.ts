import { assertEquals, assertObjectMatch, assertRejects } from "@std/assert";

import {
  buildReplayIdentifyPayload,
  invokeIdentifyMultimodalReplay,
  MINIMUM_REPLAY_LEASE_SECONDS,
  REPLAY_IDENTIFY_TIMEOUT_MS,
  REPLAY_LEASE_SAFETY_MARGIN_MS,
  replayScanIngestion,
} from "./worker.ts";
import type { ReplayableScanIngestionRow, ReplayScanRow } from "./db.ts";

const CURRENT_SECRET_KEY = [
  "sb",
  "secret",
  "service-role",
  "a".repeat(20),
].join("_");

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
      schemaVersion: 2,
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
        ownerMediaTimeline: [
          { kind: "video", clipIndex: 0 },
          { kind: "description", contextIndex: 0 },
        ],
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
  assertEquals(payload.ownerMediaTimeline, [
    { kind: "video", clipIndex: 0 },
    { kind: "description", contextIndex: 0 },
  ]);
  assertEquals(Array.isArray(payload.observation_contexts), true);
});

Deno.test("buildReplayIdentifyPayload omits the owner timeline for legacy intents", () => {
  const row = replayRow({
    request_payload: {
      schemaVersion: 1,
      clientScanId: "scan-1",
      endpoint: "identify-multimodal",
      media: {
        audioR2ObjectKeys: ["staging/user-1/audio.wav"],
        audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      },
      observationContexts: [],
    },
  });

  const payload = buildReplayIdentifyPayload(row);
  assertEquals("ownerMediaTimeline" in payload, false);
});

Deno.test("identify replay carries a deadline and bounds provider errors", async () => {
  let receivedSignal: AbortSignal | undefined;
  let bodyCancelled = false;
  const oversizedBody = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(8 * 1024 + 1));
    },
    cancel() {
      bodyCancelled = true;
    },
  });
  const fetcher = ((_input: RequestInfo | URL, init?: RequestInit) => {
    receivedSignal = init?.signal ?? undefined;
    return Promise.resolve(
      new Response(oversizedBody, {
        status: 502,
      }),
    );
  }) as typeof fetch;

  await assertRejects(
    () =>
      invokeIdentifyMultimodalReplay(
        {
          identifyUrl: "https://example.test/functions/v1/identify-multimodal",
          serviceRoleKey: CURRENT_SECRET_KEY,
          payload: { client_scan_id: "scan-1" },
          userId: "user-1",
          replayAttemptCount: 1,
        },
        fetcher,
      ),
    Error,
    "identify-multimodal replay failed: 502",
  );

  assertEquals(receivedSignal instanceof AbortSignal, true);
  assertEquals(bodyCancelled, true);
});

Deno.test("replay lease always outlives its identify deadline", async () => {
  let claimedLeaseSeconds = 0;
  await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: CURRENT_SECRET_KEY,
      leaseSeconds: 1,
      awaitInvocations: true,
    },
    {
      claimJobs: (input) => {
        claimedLeaseSeconds = input.leaseSeconds;
        return Promise.resolve([]);
      },
      fetchScans: () => Promise.resolve([]),
      markComplete: () => Promise.resolve(),
      markFailure: () => Promise.resolve(),
      invokeIdentify: () => Promise.resolve(),
    },
  );

  assertEquals(claimedLeaseSeconds, MINIMUM_REPLAY_LEASE_SECONDS);
  assertEquals(
    claimedLeaseSeconds * 1000 >=
      REPLAY_IDENTIFY_TIMEOUT_MS + REPLAY_LEASE_SAFETY_MARGIN_MS,
    true,
  );
});

Deno.test("replayScanIngestion dispatches staged rows through identify", async () => {
  const invoked: unknown[] = [];
  const completed: unknown[] = [];
  const failures: unknown[] = [];

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: CURRENT_SECRET_KEY,
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
  assertObjectMatch(invoked[0] as Record<string, unknown>, {
    replayAttemptCount: 1,
  });
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
      serviceRoleKey: CURRENT_SECRET_KEY,
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

Deno.test("replayScanIngestion terminates ownerless tombstones without invoking identify", async () => {
  const invoked: unknown[] = [];
  const completed: unknown[] = [];
  const scan: ReplayScanRow = {
    id: "scan-1",
    user_id: null,
    video_storage_urls: [],
    captured_media: [],
  };

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: CURRENT_SECRET_KEY,
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
  assertEquals(completed, [{
    scanId: "scan-1",
    userId: "user-1",
    stage: "server_replay_found_ownerless_tombstone",
  }]);
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
      serviceRoleKey: CURRENT_SECRET_KEY,
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
