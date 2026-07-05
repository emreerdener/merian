import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import type { R2Config } from "../_shared/aws.ts";
import {
  buildRepairedVideoCapturedMedia,
  reconcileScanMediaAssets,
} from "./worker.ts";
import type { ReconciliationAssetRow, ReconciliationScanRow } from "./db.ts";

const NOW = new Date("2026-07-05T12:00:00.000Z");
const R2_CONFIG = {
  s3Client: {} as never,
  bucketName: "bucket",
  endpoint: "https://r2.example.test",
} satisfies R2Config;

function stagedAsset(
  overrides: Partial<ReconciliationAssetRow> = {},
): ReconciliationAssetRow {
  return {
    id: "asset-1",
    user_id: "user-1",
    client_scan_id: "00000000-0000-0000-0000-000000000001",
    scan_id: null,
    kind: "video",
    role: "playback",
    status: "staged",
    source: "capture_upload",
    url: null,
    storage_key: "staging/user-1/video.mp4",
    order_index: 0,
    content_type: "video/mp4",
    byte_size: 1_000_000,
    created_at: "2026-07-05T11:30:00.000Z",
    updated_at: "2026-07-05T11:30:00.000Z",
    ...overrides,
  };
}

function scanRow(
  overrides: Partial<ReconciliationScanRow> = {},
): ReconciliationScanRow {
  return {
    id: "00000000-0000-0000-0000-000000000001",
    user_id: "user-1",
    image_storage_urls: [
      "https://media.merian.app/public_uploads/pro/user-1/frame-1.webp",
      "https://media.merian.app/public_uploads/pro/user-1/frame-2.webp",
      "https://media.merian.app/public_uploads/pro/user-1/frame-3.webp",
      "https://media.merian.app/public_uploads/pro/user-1/frame-4.webp",
      "https://media.merian.app/public_uploads/pro/user-1/frame-5.webp",
    ],
    video_storage_urls: [],
    captured_media: null,
    inference_tier: "pro",
    ...overrides,
  };
}

function noopRecordRun() {
  return Promise.resolve();
}

Deno.test("buildRepairedVideoCapturedMedia collapses sampled frames behind a playback video", () => {
  const capturedMedia = buildRepairedVideoCapturedMedia(scanRow(), [
    "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
  ]);

  assertEquals(capturedMedia?.length, 1);
  assertEquals(capturedMedia?.[0], {
    video: {
      _0: {
        video: {
          storage: "remoteURL",
          path: "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
        },
        thumbnail: {
          storage: "remoteURL",
          path:
            "https://media.merian.app/public_uploads/pro/user-1/frame-1.webp",
        },
      },
    },
  });
});

Deno.test("reconcileScanMediaAssets repairs an existing scan with a stranded playback video", async () => {
  const promotedInputs: unknown[] = [];
  const scanUpdates: unknown[] = [];
  const promotedAssets: unknown[] = [];
  const refreshedScans: string[] = [];

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () => Promise.resolve([stagedAsset()]),
    fetchScans: () => Promise.resolve([scanRow()]),
    headObject: () => Promise.resolve(new Response(null, { status: 200 })),
    promoteMedia: (input) => {
      promotedInputs.push(input);
      return Promise.resolve([
        "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
      ]);
    },
    updateScanMedia: (scanId, videoStorageUrls, capturedMedia) => {
      scanUpdates.push({ scanId, videoStorageUrls, capturedMedia });
      return Promise.resolve();
    },
    markPromoted: (assetId, scanId, publicUrl) => {
      promotedAssets.push({ assetId, scanId, publicUrl });
      return Promise.resolve();
    },
    refreshAssets: (scanId) => {
      refreshedScans.push(scanId);
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.promoted, 1);
  assertEquals(result.repairedVideoScans, 1);
  assertEquals(result.errors, []);
  assertEquals(promotedInputs.length, 1);
  assertEquals(scanUpdates.length, 1);
  assertEquals(promotedAssets, [{
    assetId: "asset-1",
    scanId: "00000000-0000-0000-0000-000000000001",
    publicUrl: "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
  }]);
  assertEquals(refreshedScans, ["00000000-0000-0000-0000-000000000001"]);
});

Deno.test("reconcileScanMediaAssets garbage-collects abandoned staged uploads", async () => {
  const deletedKeys: string[] = [];
  const failedAssets: unknown[] = [];

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () =>
      Promise.resolve([
        stagedAsset({ created_at: "2026-07-03T23:00:00.000Z" }),
      ]),
    fetchScans: () => Promise.resolve([]),
    headObject: () => Promise.resolve(new Response(null, { status: 200 })),
    deleteObject: (key) => {
      deletedKeys.push(key);
      return Promise.resolve(new Response(null, { status: 204 }));
    },
    markFailed: (assetId, failureReason, objectDeleted) => {
      failedAssets.push({ assetId, failureReason, objectDeleted });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.deletedStagingObjects, 1);
  assertEquals(result.failedAssets, 1);
  assertEquals(deletedKeys, ["staging/user-1/video.mp4"]);
  assertEquals(failedAssets, [{
    assetId: "asset-1",
    failureReason: "scan_missing_after_ttl",
    objectDeleted: true,
  }]);
});

Deno.test("reconcileScanMediaAssets leaves recent orphan uploads for client retry", async () => {
  let headCalled = false;

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () => Promise.resolve([stagedAsset()]),
    fetchScans: () => Promise.resolve([]),
    headObject: () => {
      headCalled = true;
      return Promise.resolve(new Response(null, { status: 200 }));
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.stillPending, 1);
  assertEquals(result.failedAssets, 0);
  assert(!headCalled);
});

Deno.test("reconcileScanMediaAssets deletes consumed audio staging when the scan exists", async () => {
  const deletedKeys: string[] = [];
  const deletedAssets: unknown[] = [];

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () =>
      Promise.resolve([
        stagedAsset({
          id: "audio-asset",
          kind: "audio",
          role: "audio",
          storage_key: "staging/user-1/video-audio.wav",
          content_type: "audio/wav",
        }),
      ]),
    fetchScans: () => Promise.resolve([scanRow()]),
    deleteObject: (key) => {
      deletedKeys.push(key);
      return Promise.resolve(new Response(null, { status: 204 }));
    },
    markDeleted: (assetId, scanId) => {
      deletedAssets.push({ assetId, scanId });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.deletedStagingObjects, 1);
  assertEquals(deletedKeys, ["staging/user-1/video-audio.wav"]);
  assertEquals(deletedAssets, [{
    assetId: "audio-asset",
    scanId: "00000000-0000-0000-0000-000000000001",
  }]);
});
