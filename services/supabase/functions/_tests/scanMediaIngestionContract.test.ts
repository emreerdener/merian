import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import { buildCompatibilityScanIngestionIntent } from "../_shared/scanIngestionCompatibility.ts";
import { hasRequiredVideoMedia } from "../check-scan-status/status.ts";
import {
  buildReplayIdentifyPayload,
  replayScanIngestion,
} from "../replay-scan-ingestion/worker.ts";
import {
  buildRestoredVideoCapturedMedia,
  type ShareEligibleScanRow,
} from "../share-scan-to-explore/db.ts";
import type { ReplayableScanIngestionRow } from "../replay-scan-ingestion/db.ts";

const USER_ID = "00000000-0000-4000-8000-000000000001";
const SCAN_ID = "11111111-1111-4111-8111-111111111111";
const IMAGE_URL = "https://media.merian.app/public_uploads/pro/user/image.webp";
const VIDEO_URL = "https://media.merian.app/public_uploads/pro/user/video.mp4";
const AUDIO_KEY = "staging/user/audio.wav";
const IMAGE_KEY = "staging/user/image.webp";
const VIDEO_KEY = "staging/user/video.mp4";

Deno.test("scan media ingestion contract matrix keeps resumable scan types replayable", async () => {
  const cases = [
    {
      name: "staged image compatibility",
      input: {
        scanId: `${SCAN_ID}`,
        endpoint: "identify" as const,
        imageKeys: [IMAGE_KEY],
        description: "Observed near a shaded creek.",
        visualMediaItems: [{ kind: "image", sourceIndex: 0 }],
      },
      expected: {
        imageCount: 1,
        audioCount: 0,
        videoCount: 0,
        requiredVideoCount: 0,
        replayKeys: { images: [IMAGE_KEY], audio: [], video: [] },
      },
    },
    {
      name: "staged audio compatibility",
      input: {
        scanId: `${SCAN_ID}`,
        endpoint: "audio-spec" as const,
        audioKeys: [AUDIO_KEY],
        audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
      },
      expected: {
        imageCount: 0,
        audioCount: 1,
        videoCount: 0,
        requiredVideoCount: 0,
        replayKeys: { images: [], audio: [AUDIO_KEY], video: [] },
      },
    },
    {
      name: "text-only compatibility",
      input: {
        scanId: `${SCAN_ID}`,
        endpoint: "identify-describe" as const,
        description: "Large bracket fungus on an old stump.",
      },
      expected: {
        imageCount: 0,
        audioCount: 0,
        videoCount: 0,
        requiredVideoCount: 0,
        replayKeys: { images: [], audio: [], video: [] },
      },
    },
    {
      name: "video with sampled inference frames and playback mp4",
      input: {
        scanId: `${SCAN_ID}`,
        endpoint: "identify" as const,
        imageKeys: [
          "staging/user/video-frame-0.webp",
          "staging/user/video-frame-1.webp",
          "staging/user/video-frame-2.webp",
          "staging/user/video-frame-3.webp",
          "staging/user/video-frame-4.webp",
        ],
        audioKeys: [AUDIO_KEY],
        videoKeys: [VIDEO_KEY],
        requiredVideoCount: 1,
        videoFrameCount: 5,
        videoInferenceFrameCount: 5,
        visualMediaItems: Array.from({ length: 5 }, (_, frameIndex) => ({
          kind: "video_frame",
          sourceIndex: frameIndex,
          clipIndex: 0,
          frameIndex,
        })),
        audioMediaItems: [{
          kind: "video_audio",
          sourceIndex: 0,
          clipIndex: 0,
        }],
      },
      expected: {
        imageCount: 5,
        audioCount: 1,
        videoCount: 1,
        requiredVideoCount: 1,
        replayKeys: {
          images: [
            "staging/user/video-frame-0.webp",
            "staging/user/video-frame-1.webp",
            "staging/user/video-frame-2.webp",
            "staging/user/video-frame-3.webp",
            "staging/user/video-frame-4.webp",
          ],
          audio: [AUDIO_KEY],
          video: [VIDEO_KEY],
        },
      },
    },
  ];

  for (const testCase of cases) {
    const intent = await buildCompatibilityScanIngestionIntent(testCase.input);
    assertEquals(intent.resumable, true, testCase.name);
    assertEquals(intent.inlineMediaRedacted, false, testCase.name);
    assertEquals(intent.mediaCounts.image_count, testCase.expected.imageCount);
    assertEquals(intent.mediaCounts.audio_count, testCase.expected.audioCount);
    assertEquals(intent.mediaCounts.video_count, testCase.expected.videoCount);
    assertEquals(
      intent.mediaCounts.required_video_count,
      testCase.expected.requiredVideoCount,
    );

    const replayPayload = buildReplayIdentifyPayload(rowForIntent(intent));
    assertEquals(replayPayload.client_scan_id, SCAN_ID, testCase.name);
    assertEquals(
      replayPayload.r2ObjectKeys,
      testCase.expected.replayKeys.images,
    );
    assertEquals(
      replayPayload.audioR2ObjectKeys,
      testCase.expected.replayKeys.audio,
    );
    assertEquals(
      replayPayload.videoR2ObjectKeys,
      testCase.expected.replayKeys.video,
    );

    if (testCase.expected.requiredVideoCount > 0) {
      assertEquals(replayPayload.videoFrameCount, 5);
      assertEquals(
        Array.isArray(replayPayload.visualMediaItems) &&
          replayPayload.visualMediaItems.length,
        5,
      );
    }
  }
});

Deno.test("scan media ingestion contract keeps inline media client-owned", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: SCAN_ID,
    endpoint: "identify",
    inlineImageCount: 1,
    inlineAudioCount: 1,
    description: "Foreground media bytes were present.",
  });

  assertEquals(intent.resumable, false);
  assertEquals(intent.inlineMediaRedacted, true);
  assertEquals(intent.redactedMediaCounts, {
    image_base64_count: 1,
    audio_base64_count: 1,
  });
  const payloadJson = JSON.stringify(intent.requestPayload);
  assertEquals(payloadJson.includes("imageBase64s"), false);
  assertEquals(payloadJson.includes("audioBase64s"), false);
});

Deno.test("scan media ingestion contract rejects frame-only video completion and accepts durable playback", () => {
  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: [],
      captured_media: fiveFrameImageManifest(),
      media_assets: [],
    }, 1),
    false,
  );

  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: [VIDEO_URL],
      captured_media: [{
        video: {
          _0: {
            video: { storage: "remoteURL", path: VIDEO_URL },
            thumbnail: { storage: "remoteURL", path: IMAGE_URL },
          },
        },
      }],
      media_assets: [],
    }, 1),
    true,
  );

  assertEquals(
    hasRequiredVideoMedia({
      video_storage_urls: [VIDEO_URL],
      captured_media: fiveFrameImageManifest(),
      media_assets: [{
        kind: "video",
        role: "playback",
        status: "ready",
        url: VIDEO_URL,
        thumbnail_url: IMAGE_URL,
        order_index: 0,
      }],
    }, 1),
    true,
  );
});

Deno.test("scan media ingestion contract keeps Explore video share source paired with thumbnail", () => {
  const scan = shareScanRow({
    image_storage_urls: [
      `${IMAGE_URL}?frame=0`,
      `${IMAGE_URL}?frame=1`,
      `${IMAGE_URL}?frame=2`,
      `${IMAGE_URL}?frame=3`,
      `${IMAGE_URL}?frame=4`,
    ],
    video_storage_urls: [VIDEO_URL],
    captured_media: null,
  });

  const capturedMedia = buildRestoredVideoCapturedMedia(scan, [VIDEO_URL]);
  assert(Array.isArray(capturedMedia));
  assertEquals(capturedMedia.length, 1);

  const mediaRows = buildExplorePostMediaRows({
    id: SCAN_ID,
    image_storage_urls: scan.image_storage_urls,
    video_storage_urls: [VIDEO_URL],
    captured_media: capturedMedia,
    media_assets: [],
  }, [{
    kind: "video",
    source_media_id: `scan:${SCAN_ID}:video:0`,
    order_index: 0,
  }]);

  assertEquals(mediaRows, [{
    kind: "video",
    url: VIDEO_URL,
    thumbnail_url: `${IMAGE_URL}?frame=0`,
    order_index: 0,
    duration_seconds: null,
    has_audio: false,
  }]);
});

Deno.test("scan media ingestion contract leaves existing incomplete video scans for repair", async () => {
  const intent = await buildCompatibilityScanIngestionIntent({
    scanId: SCAN_ID,
    endpoint: "identify",
    imageKeys: ["staging/user/video-frame-0.webp"],
    videoKeys: [VIDEO_KEY],
    requiredVideoCount: 1,
    videoFrameCount: 1,
  });
  const row = rowForIntent(intent);
  const failures: Array<{ stage: string; errorMessage: string }> = [];

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: "service-role",
      awaitInvocations: true,
    },
    {
      claimJobs: () => Promise.resolve([row]),
      fetchScans: () =>
        Promise.resolve([{
          id: SCAN_ID,
          user_id: USER_ID,
          video_storage_urls: [],
          captured_media: fiveFrameImageManifest(),
        }]),
      markComplete: () => Promise.resolve(),
      markFailure: (input) => {
        failures.push({
          stage: input.stage,
          errorMessage: input.errorMessage,
        });
        return Promise.resolve();
      },
      invokeIdentify: () => {
        throw new Error("Replay should not run against incomplete scan rows.");
      },
    },
  );

  assertEquals(result.dispatched, 0);
  assertEquals(result.skippedExistingIncomplete, 1);
  assertEquals(failures, [{
    stage: "server_replay_existing_scan_media_incomplete",
    errorMessage:
      "Cloud scan row exists but required media is incomplete; reconciliation must repair it.",
  }]);
});

Deno.test("scan media ingestion contract rejects replay payloads without evidence", async () => {
  const row: ReplayableScanIngestionRow = {
    scan_id: SCAN_ID,
    user_id: USER_ID,
    endpoint: "identify-multimodal",
    status: "retrying",
    stage: "server_replay_claimed",
    attempt_count: 1,
    media_counts: {},
    media_object_keys: {},
    upload_session_ids: [],
    manifest_checksum: null,
    request_payload: {
      clientScanId: SCAN_ID,
      media: {},
      observationContexts: [],
    },
    payload_checksum: null,
    replay_attempt_count: 1,
  };
  const failures: Array<{ stage: string; terminal?: boolean }> = [];

  const result = await replayScanIngestion(
    {} as never,
    {
      identifyUrl: "https://example.test/functions/v1/identify-multimodal",
      serviceRoleKey: "service-role",
      awaitInvocations: true,
    },
    {
      claimJobs: () => Promise.resolve([row]),
      fetchScans: () => Promise.resolve([]),
      markComplete: () => Promise.resolve(),
      markFailure: (input) => {
        failures.push({ stage: input.stage, terminal: input.terminal });
        return Promise.resolve();
      },
      invokeIdentify: () => Promise.resolve(),
    },
  );

  assertEquals(result.failedDispatches, 1);
  assertEquals(failures, [{
    stage: "server_replay_payload_invalid",
    terminal: true,
  }]);
});

Deno.test("scan media ingestion contract rejects Explore video without thumbnail", () => {
  assertThrows(
    () => {
      buildExplorePostMediaRows({
        id: SCAN_ID,
        image_storage_urls: [],
        video_storage_urls: [VIDEO_URL],
        captured_media: [{
          video: {
            _0: {
              video: { storage: "remoteURL", path: VIDEO_URL },
            },
          },
        }],
        media_assets: [],
      }, [{
        kind: "video",
        source_media_id: `scan:${SCAN_ID}:video:0`,
        order_index: 0,
      }]);
    },
    Error,
    "Video thumbnail unavailable.",
  );
});

function rowForIntent(
  intent: Awaited<ReturnType<typeof buildCompatibilityScanIngestionIntent>>,
): ReplayableScanIngestionRow {
  return {
    scan_id: SCAN_ID,
    user_id: USER_ID,
    endpoint: "identify-multimodal",
    status: "retrying",
    stage: "server_replay_claimed",
    attempt_count: 1,
    media_counts: { ...intent.mediaCounts },
    media_object_keys: { ...intent.mediaObjectKeys },
    upload_session_ids: intent.uploadSessionIds,
    manifest_checksum: intent.manifestChecksum,
    request_payload: intent.requestPayload,
    payload_checksum: intent.payloadChecksum,
    replay_attempt_count: 1,
  };
}

function shareScanRow(
  overrides: Partial<ShareEligibleScanRow>,
): ShareEligibleScanRow {
  return {
    id: SCAN_ID,
    user_id: USER_ID,
    geoprivacy: "open",
    image_storage_urls: [],
    video_storage_urls: [],
    captured_media: null,
    is_tombstoned: false,
    species_id: "22222222-2222-4222-8222-222222222222",
    confirmed_species_id: null,
    ...overrides,
  };
}

function fiveFrameImageManifest(): unknown[] {
  return Array.from({ length: 5 }, (_, index) => ({
    image: {
      _0: {
        storage: "remoteURL",
        path: `${IMAGE_URL}?frame=${index}`,
      },
    },
  }));
}
