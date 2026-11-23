import { assert, assertEquals } from "@std/assert";

import type { R2Config } from "../_shared/aws.ts";
import {
  buildRepairedVideoCapturedMedia,
  reconcileScanMediaAssets,
} from "./worker.ts";
import type {
  ReconciliationAssetRow,
  ReconciliationJobRow,
  ReconciliationScanRow,
} from "./db.ts";

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
    audio_storage_urls: [],
    captured_media: null,
    inference_tier: "pro",
    ...overrides,
  };
}

function jobRow(
  overrides: Partial<ReconciliationJobRow> = {},
): ReconciliationJobRow {
  return {
    scan_id: "00000000-0000-0000-0000-000000000001",
    user_id: "user-1",
    status: "failed_retryable",
    stage: "video_promotion_failed",
    media_counts: { required_video_count: 1 },
    lock_expires_at: null,
    retry_after: null,
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

Deno.test("buildRepairedVideoCapturedMedia preserves nonvisual timeline items", () => {
  const description = {
    description: { _0: { freeText: "A note before the video" } },
  };
  const audio = {
    audio: {
      _0: {
        storage: "remoteURL" as const,
        path: "https://media.merian.app/field.wav",
        sourceIndex: 0,
      },
    },
  };
  const scan = scanRow({
    captured_media: [
      description,
      ...[1, 2, 3, 4, 5].map((index) => ({
        image: {
          _0: {
            storage: "remoteURL",
            path:
              `https://media.merian.app/public_uploads/pro/user-1/frame-${index}.webp`,
          },
        },
      })),
      audio,
    ],
  });

  const capturedMedia = buildRepairedVideoCapturedMedia(scan, [
    "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
  ]);

  assertEquals(capturedMedia?.[0], description);
  assertEquals(Object.hasOwn(capturedMedia?.[1] as object, "video"), true);
  assertEquals(capturedMedia?.[2], audio);
});

Deno.test("video reconciliation writes only canonical captured media", () => {
  const scan = scanRow({
    captured_media: [
      {
        description: {
          _0: { free_text: "  Before repair  ", addedAt: 807_000_000 },
        },
      },
      {
        audio: {
          _0: { storage: "localFile", path: "unusable.wav" },
        },
      },
    ],
  });

  assertEquals(
    buildRepairedVideoCapturedMedia(scan, [
      "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
    ]),
    [
      { description: { _0: { freeText: "Before repair" } } },
      {
        video: {
          _0: {
            video: {
              storage: "remoteURL",
              path:
                "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
            },
            thumbnail: {
              storage: "remoteURL",
              path:
                "https://media.merian.app/public_uploads/pro/user-1/frame-1.webp",
            },
          },
        },
      },
    ],
  );
});

Deno.test("reconcileScanMediaAssets previews a stranded playback video without repair", async () => {
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
    fetchJobs: () => Promise.resolve([]),
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
  assertEquals(result.preview.promoted, 1);
  assertEquals(result.preview.repairedVideoScans, 1);
  assertEquals(result.errors, []);
  assertEquals(promotedInputs.length, 0);
  assertEquals(scanUpdates.length, 0);
  assertEquals(promotedAssets, []);
  assertEquals(refreshedScans, []);
});

Deno.test("reconcileScanMediaAssets previews abandoned staged uploads without deletion", async () => {
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
    fetchJobs: () => Promise.resolve([]),
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
  assertEquals(result.preview.deletedStagingObjects, 1);
  assertEquals(result.preview.failedAssets, 1);
  assertEquals(deletedKeys, []);
  assertEquals(failedAssets, []);
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
    fetchJobs: () => Promise.resolve([]),
    headObject: () => {
      headCalled = true;
      return Promise.resolve(new Response(null, { status: 200 }));
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.stillPending, 1);
  assertEquals(result.preview.failedAssets, 0);
  assert(!headCalled);
});

Deno.test("reconcileScanMediaAssets retains audio when companion role is unproven", async () => {
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
        stagedAsset({
          id: "audio-asset",
          kind: "audio",
          role: "audio",
          storage_key: "staging/user-1/video-audio.wav",
          content_type: "audio/wav",
        }),
      ]),
    fetchScans: () => Promise.resolve([scanRow()]),
    fetchJobs: () => Promise.resolve([]),
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
  assertEquals(result.preview.deletedStagingObjects, 0);
  assertEquals(result.preview.failedAssets, 1);
  assertEquals(deletedKeys, []);
  assertEquals(failedAssets, []);
});

Deno.test("reconcileScanMediaAssets preserves promoted standalone audio", async () => {
  const promotedAssets: unknown[] = [];
  let deleteCalled = false;
  const publicUrl =
    "https://media.merian.app/public_uploads/pro/user-1/field-audio.wav";

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () =>
      Promise.resolve([
        stagedAsset({
          id: "standalone-audio-asset",
          kind: "audio",
          role: "audio",
          storage_key: "staging/user-1/field-audio.wav",
          content_type: "audio/wav",
        }),
      ]),
    fetchScans: () =>
      Promise.resolve([scanRow({ audio_storage_urls: [publicUrl] })]),
    fetchJobs: () => Promise.resolve([]),
    deleteObject: () => {
      deleteCalled = true;
      return Promise.resolve(new Response(null, { status: 204 }));
    },
    markPromoted: (assetId, scanId, promotedUrl) => {
      promotedAssets.push({ assetId, scanId, promotedUrl });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.preview.promoted, 1);
  assertEquals(result.preview.deletedStagingObjects, 0);
  assertEquals(deleteCalled, false);
  assertEquals(promotedAssets, []);
});

Deno.test("reconcileScanMediaAssets waits when an ingestion job still owns pending media", async () => {
  let headCalled = false;

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
    fetchJobs: () =>
      Promise.resolve([
        jobRow({
          status: "finalizing",
          stage: "video_promotion_started",
          lock_expires_at: "2026-07-05T12:03:00.000Z",
        }),
      ]),
    headObject: () => {
      headCalled = true;
      return Promise.resolve(new Response(null, { status: 200 }));
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.stillPending, 1);
  assertEquals(result.preview.failedAssets, 0);
  assert(!headCalled);
});

Deno.test("reconcileScanMediaAssets does not let another user's job hold media", async () => {
  let headCalled = false;

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
    fetchJobs: () =>
      Promise.resolve([
        jobRow({
          user_id: "user-2",
          status: "finalizing",
          stage: "video_promotion_started",
          lock_expires_at: "2026-07-05T12:03:00.000Z",
        }),
      ]),
    headObject: () => {
      headCalled = true;
      return Promise.resolve(new Response(null, { status: 404 }));
    },
    markFailed: () => Promise.resolve(),
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.stillPending, 1);
  assertEquals(result.preview.stillPending, 0);
  assertEquals(result.preview.failedAssets, 1);
  assert(headCalled);
});

Deno.test("reconcileScanMediaAssets keeps abandoned ingestion jobs unchanged", async () => {
  const failedJobs: unknown[] = [];

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
    fetchJobs: () => Promise.resolve([jobRow()]),
    headObject: () => Promise.resolve(new Response(null, { status: 404 })),
    markFailed: () => Promise.resolve(),
    markJobFailed: (scanId, userId, failureReason) => {
      failedJobs.push({ scanId, userId, failureReason });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.preview.failedAssets, 1);
  assertEquals(result.missingObjects, 1);
  assertEquals(failedJobs, []);
});

Deno.test("reconcileScanMediaAssets never rewrites an existing terminal decision", async () => {
  const failedJobs: unknown[] = [];

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
    fetchJobs: () =>
      Promise.resolve([
        jobRow({
          status: "failed_terminal",
          stage: "moderation_rejected",
        }),
      ]),
    headObject: () => Promise.resolve(new Response(null, { status: 404 })),
    markFailed: () => Promise.resolve(),
    markJobFailed: (scanId, userId, failureReason) => {
      failedJobs.push({ scanId, userId, failureReason });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.preview.failedAssets, 1);
  assertEquals(result.missingObjects, 1);
  assertEquals(failedJobs, []);
});

Deno.test("reconcileScanMediaAssets keeps previewed complete jobs unchanged", async () => {
  const completedJobs: unknown[] = [];

  const result = await reconcileScanMediaAssets({} as never, {
    now: NOW,
    repairAfterMinutes: 15,
    abandonAfterHours: 36,
  }, {
    r2Config: R2_CONFIG,
    fetchAssets: () => Promise.resolve([stagedAsset()]),
    fetchScans: () => Promise.resolve([scanRow()]),
    fetchJobs: () => Promise.resolve([jobRow()]),
    headObject: () => Promise.resolve(new Response(null, { status: 200 })),
    promoteMedia: () =>
      Promise.resolve([
        "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
      ]),
    updateScanMedia: () => Promise.resolve(),
    markPromoted: () => Promise.resolve(),
    refreshAssets: () => Promise.resolve(),
    markJobComplete: (scanId, userId) => {
      completedJobs.push({ scanId, userId });
      return Promise.resolve();
    },
    recordRun: noopRecordRun,
  });

  assertEquals(result.scanned, 1);
  assertEquals(result.preview.repairedVideoScans, 1);
  assertEquals(completedJobs, []);
});

Deno.test("quarantine cannot be bypassed by request flags or any candidate branch", async (test) => {
  const cases: Array<{
    name: string;
    asset?: Partial<ReconciliationAssetRow>;
    scan?: Partial<ReconciliationScanRow> | null;
    job?: Partial<ReconciliationJobRow> | null;
    exists?: boolean;
  }> = [
    { name: "stranded-video" },
    { name: "missing-video", exists: false },
    { name: "missing-key", asset: { storage_key: null } },
    { name: "foreign-owner", scan: { user_id: "user-2" } },
    { name: "unknown-role", asset: { role: "audio" } },
    { name: "unmatched-image", asset: { kind: "image" } },
    { name: "missing-image", asset: { kind: "image" }, exists: false },
    {
      name: "matched-image",
      asset: { kind: "image" },
      scan: {
        image_storage_urls: [
          "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
        ],
      },
    },
    {
      name: "matched-video",
      scan: {
        video_storage_urls: [
          "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
        ],
      },
    },
    { name: "unproven-audio", asset: { kind: "audio", role: "audio" } },
    {
      name: "matched-audio",
      asset: { kind: "audio", role: "audio" },
      scan: {
        audio_storage_urls: [
          "https://media.merian.app/public_uploads/pro/user-1/video.mp4",
        ],
      },
    },
    { name: "abandoned-without-job", scan: null, job: null },
    { name: "abandoned-with-job", scan: null },
    { name: "abandoned-missing-object", scan: null, exists: false },
    { name: "terminal-job", scan: null, job: { status: "failed_terminal" } },
    { name: "completed-job", job: { status: "complete" } },
    {
      name: "active-job",
      scan: null,
      job: {
        lock_expires_at: "2026-07-05T13:00:00.000Z",
        status: "finalizing",
      },
    },
  ];
  for (const dryRun of [undefined, false, true]) {
    for (const scenario of cases) {
      await test.step(`${scenario.name}/${dryRun}`, async () => {
        const effects: string[] = [];
        const forbidden = (name: string) => (): never => {
          effects.push(name);
          throw new Error(`Forbidden effect: ${name}`);
        };
        let audited = false;
        const result = await reconcileScanMediaAssets({} as never, {
          now: NOW,
          dryRun,
        }, {
          r2Config: R2_CONFIG,
          fetchAssets: () =>
            Promise.resolve([stagedAsset({
              created_at: "2026-07-03T23:00:00.000Z",
              ...scenario.asset,
            })]),
          fetchScans: () =>
            Promise.resolve(
              scenario.scan === null ? [] : [scanRow(scenario.scan)],
            ),
          fetchJobs: () =>
            Promise.resolve(
              scenario.job === null ? [] : [jobRow(scenario.job)],
            ),
          headObject: () =>
            Promise.resolve(
              new Response(null, {
                status: scenario.exists === false ? 404 : 200,
              }),
            ),
          deleteObject: forbidden("delete"),
          promoteMedia: forbidden("copy-or-put"),
          markPromoted: forbidden("mark-promoted"),
          markDeleted: forbidden("mark-deleted"),
          markFailed: forbidden("mark-failed"),
          updateScanMedia: forbidden("update-scan"),
          refreshAssets: forbidden("refresh-assets"),
          markJobComplete: forbidden("complete-job"),
          markJobFailed: forbidden("fail-job"),
          recordRun: (row) => {
            audited = true;
            assertEquals(row.status, "dry_run");
            assertEquals(row.promoted_count, 0);
            assertEquals(row.repaired_video_scan_count, 0);
            assertEquals(row.deleted_staging_object_count, 0);
            assertEquals(row.failed_asset_count, 0);
            assertEquals(row.still_pending_count, 1);
            return Promise.resolve();
          },
        });
        assertEquals(effects, []);
        assertEquals(result.errors, []);
        assertEquals(result.executionMode, "quarantined");
        assertEquals(result.holdReason, "durable_object_authority_required");
        assertEquals(result.scanned, 1);
        assertEquals(result.stillPending, 1);
        assertEquals(result.promoted, 0);
        assertEquals(result.repairedVideoScans, 0);
        assertEquals(result.deletedStagingObjects, 0);
        assertEquals(result.failedAssets, 0);
        assertEquals(audited, true);
      });
    }
  }
});
