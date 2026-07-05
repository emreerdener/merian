import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  buildScanMediaHealthReport,
  type BuildScanMediaHealthReportInput,
  parseScanMediaHealthRequest,
} from "./health.ts";

const NOW = new Date("2026-07-05T15:00:00.000Z");
const BASE_REQUEST = {
  limit: 10,
  stuckAfterMinutes: 20,
  staleAssetAfterMinutes: 15,
  recentScanLimit: 250,
};

Deno.test("parseScanMediaHealthRequest applies defaults and clamps limits", () => {
  assertEquals(parseScanMediaHealthRequest({}).request, {
    limit: 25,
    stuckAfterMinutes: 20,
    staleAssetAfterMinutes: 15,
    recentScanLimit: 250,
  });

  assertEquals(
    parseScanMediaHealthRequest({
      limit: 500,
      stuck_after_minutes: 5.8,
      staleAssetAfterMinutes: 4,
      recent_scan_limit: 2_000,
    }).request,
    {
      limit: 100,
      stuckAfterMinutes: 5,
      staleAssetAfterMinutes: 4,
      recentScanLimit: 1_000,
    },
  );
});

Deno.test("parseScanMediaHealthRequest rejects invalid numeric fields", () => {
  assertObjectMatch(parseScanMediaHealthRequest({ limit: "many" }), {
    status: 400,
  });
  assertObjectMatch(parseScanMediaHealthRequest({ recent_scan_limit: 0 }), {
    status: 400,
  });
});

Deno.test("buildScanMediaHealthReport returns ok for clean media state", () => {
  const report = buildScanMediaHealthReport(baseInput({
    scans: [{
      id: "scan-1",
      user_id: "user-1",
      timestamp: "2026-07-05T14:55:00.000Z",
      image_storage_urls: ["https://media.example/frame.webp"],
      video_storage_urls: ["https://media.example/video.mp4"],
      captured_media: [{ video: { _0: {} } }],
    }],
    readyVideoAssets: [{
      id: "asset-1",
      scan_id: "scan-1",
      url: "https://media.example/video.mp4",
      thumbnail_url: "https://media.example/frame.webp",
    }],
    reconciliationRuns: [{
      id: "run-1",
      status: "success",
      error_count: 0,
      errors: [],
      started_at: "2026-07-05T14:50:00.000Z",
      finished_at: "2026-07-05T14:51:00.000Z",
    }],
  }));

  assertEquals(report.status, "ok");
  assertEquals(report.issues, []);
});

Deno.test("buildScanMediaHealthReport flags stuck jobs and video media drift", () => {
  const report = buildScanMediaHealthReport(baseInput({
    ingestionJobs: [{
      scan_id: "scan-stuck",
      user_id: "user-1",
      status: "finalizing",
      stage: "promote_video_media",
      attempt_count: 1,
      lock_expires_at: "2026-07-05T14:30:00.000Z",
      updated_at: "2026-07-05T14:20:00.000Z",
    }],
    ingestionIntents: [ingestionIntent({ scan_id: "scan-stuck" })],
    scans: [{
      id: "scan-video-missing",
      user_id: "user-1",
      timestamp: "2026-07-05T14:55:00.000Z",
      image_storage_urls: ["https://media.example/frame.webp"],
      video_storage_urls: ["https://media.example/video.mp4"],
      captured_media: [{ image: { _0: {} } }],
    }],
    readyVideoAssets: [],
    exploreVideoMedia: [{
      id: "post-media-1",
      post_id: "post-1",
      url: "https://media.example/video.mp4",
      thumbnail_url: null,
      updated_at: "2026-07-05T14:59:00.000Z",
    }],
  }));

  assertEquals(report.status, "critical");
  assertEquals(
    report.issues.map((issue) => issue.code),
    [
      "stuck_ingestion_jobs",
      "video_scan_missing_captured_media_video",
      "video_scan_missing_ready_playback_asset",
      "explore_video_missing_thumbnail",
    ],
  );
});

Deno.test("buildScanMediaHealthReport flags frame-only video smells as warning", () => {
  const report = buildScanMediaHealthReport(baseInput({
    ingestionJobs: [{
      scan_id: "scan-frame-only",
      user_id: "user-1",
      status: "complete",
      stage: "complete",
      attempt_count: 1,
      media_counts: { required_video_count: 1 },
      updated_at: "2026-07-05T14:59:00.000Z",
    }],
    scans: [{
      id: "scan-frame-only",
      user_id: "user-1",
      timestamp: "2026-07-05T14:55:00.000Z",
      image_storage_urls: [
        "https://media.example/frame-1.webp",
        "https://media.example/frame-2.webp",
        "https://media.example/frame-3.webp",
        "https://media.example/frame-4.webp",
        "https://media.example/frame-5.webp",
      ],
      video_storage_urls: [],
      captured_media: [
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
      ],
    }],
  }));

  assertEquals(report.status, "warning");
  assertEquals(report.issues[0].code, "frame_only_video_smells");
});

Deno.test("buildScanMediaHealthReport flags missing and redacted ingestion intents", () => {
  const report = buildScanMediaHealthReport(baseInput({
    ingestionJobs: [
      {
        scan_id: "scan-missing-intent",
        user_id: "user-1",
        status: "failed_retryable",
        stage: "video_promotion_failed",
        attempt_count: 2,
        retry_after: "2026-07-05T14:50:00.000Z",
        updated_at: "2026-07-05T14:49:00.000Z",
      },
      {
        scan_id: "scan-inline-intent",
        user_id: "user-1",
        status: "processing",
        stage: "ai_inference_started",
        attempt_count: 1,
        lock_expires_at: "2026-07-05T15:05:00.000Z",
        updated_at: "2026-07-05T14:58:00.000Z",
      },
    ],
    ingestionIntents: [
      ingestionIntent({
        scan_id: "scan-inline-intent",
        resumable: false,
        inline_media_redacted: true,
        redacted_media_counts: { image_base64_count: 1 },
      }),
    ],
  }));

  assertEquals(report.status, "warning");
  assertEquals(
    report.issues.map((issue) => issue.code),
    [
      "retryable_ingestion_jobs_past_due",
      "ingestion_jobs_missing_intent",
      "ingestion_intents_not_resumable",
    ],
  );
  assertEquals(report.counts.ingestion_intents_checked, 1);
});

Deno.test("buildScanMediaHealthReport ignores ordinary five-image scans", () => {
  const report = buildScanMediaHealthReport(baseInput({
    scans: [{
      id: "scan-five-images",
      user_id: "user-1",
      timestamp: "2026-07-05T14:55:00.000Z",
      image_storage_urls: [
        "https://media.example/image-1.webp",
        "https://media.example/image-2.webp",
        "https://media.example/image-3.webp",
        "https://media.example/image-4.webp",
        "https://media.example/image-5.webp",
      ],
      video_storage_urls: [],
      captured_media: [
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
        { image: { _0: {} } },
      ],
    }],
  }));

  assertEquals(report.status, "ok");
  assertEquals(report.issues, []);
});

Deno.test("buildScanMediaHealthReport groups stale and failed assets by media kind and role", () => {
  const report = buildScanMediaHealthReport(baseInput({
    staleCaptureUploadAssets: [
      mediaAsset({ id: "asset-a", kind: "image", role: "display" }),
      mediaAsset({ id: "asset-b", kind: "image", role: "display" }),
      mediaAsset({ id: "asset-c", kind: "audio", role: "audio" }),
    ],
    failedAssets: [
      mediaAsset({
        id: "asset-d",
        kind: "video",
        role: "playback",
        status: "failed",
      }),
      mediaAsset({
        id: "asset-e",
        kind: "image",
        role: "thumbnail",
        status: "failed",
      }),
    ],
  }));

  assertEquals(report.status, "warning");
  assertEquals(report.asset_breakdown.stale_capture_upload_assets, [
    { kind: "audio", role: "audio", count: 1 },
    { kind: "image", role: "display", count: 2 },
  ]);
  assertEquals(report.asset_breakdown.failed_assets, [
    { kind: "image", role: "thumbnail", count: 1 },
    { kind: "video", role: "playback", count: 1 },
  ]);
});

function baseInput(
  overrides: Partial<BuildScanMediaHealthReportInput> = {},
): BuildScanMediaHealthReportInput {
  return {
    now: NOW,
    request: BASE_REQUEST,
    ingestionJobs: [],
    ingestionIntents: [],
    staleCaptureUploadAssets: [],
    failedAssets: [],
    scans: [],
    readyVideoAssets: [],
    exploreVideoMedia: [],
    reconciliationRuns: [],
    ...overrides,
  };
}

function ingestionIntent(
  overrides: Partial<
    BuildScanMediaHealthReportInput["ingestionIntents"][number]
  >,
): BuildScanMediaHealthReportInput["ingestionIntents"][number] {
  return {
    scan_id: overrides.scan_id ?? "scan-1",
    user_id: overrides.user_id ?? "user-1",
    manifest_checksum: overrides.manifest_checksum ?? "manifest",
    payload_checksum: overrides.payload_checksum ?? "payload",
    resumable: overrides.resumable ?? true,
    inline_media_redacted: overrides.inline_media_redacted ?? false,
    redacted_media_counts: overrides.redacted_media_counts ?? {},
    updated_at: overrides.updated_at ?? "2026-07-05T14:59:00.000Z",
  };
}

function mediaAsset(
  overrides: Partial<
    BuildScanMediaHealthReportInput["staleCaptureUploadAssets"][number]
  >,
): BuildScanMediaHealthReportInput["staleCaptureUploadAssets"][number] {
  return {
    id: overrides.id ?? "asset-1",
    scan_id: overrides.scan_id ?? null,
    client_scan_id: overrides.client_scan_id ?? "scan-1",
    user_id: overrides.user_id ?? "user-1",
    kind: overrides.kind ?? "image",
    role: overrides.role ?? "display",
    status: overrides.status ?? "staged",
    source: overrides.source ?? "capture_upload",
    url: overrides.url ?? null,
    storage_key: overrides.storage_key ?? "staging/user-1/media.webp",
    thumbnail_url: overrides.thumbnail_url ?? null,
    failure_reason: overrides.failure_reason ?? null,
    created_at: overrides.created_at ?? "2026-07-05T14:00:00.000Z",
    updated_at: overrides.updated_at ?? "2026-07-05T14:00:00.000Z",
  };
}
