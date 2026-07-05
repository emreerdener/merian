import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  scanIngestionClientState,
  type ScanIngestionJobRow,
  scanIngestionManifestChecksum,
  scanIngestionMediaObjectKeys,
} from "./scanIngestionJobs.ts";

function jobRow(
  overrides: Partial<ScanIngestionJobRow> = {},
): ScanIngestionJobRow {
  return {
    id: "job-1",
    scan_id: "scan-1",
    user_id: "user-1",
    endpoint: "identify-multimodal",
    status: "processing",
    stage: "ai_inference_started",
    attempt_count: 2,
    media_counts: {},
    media_object_keys: {},
    upload_session_ids: [],
    manifest_checksum: null,
    locked_at: null,
    lock_expires_at: null,
    retry_after: null,
    last_error: null,
    completed_at: null,
    created_at: null,
    updated_at: null,
    ...overrides,
  };
}

Deno.test("scanIngestionMediaObjectKeys deduplicates and trims staged key arrays", () => {
  assertEquals(
    scanIngestionMediaObjectKeys({
      imageKeys: [" staging/user/a.webp ", "", "staging/user/a.webp"],
      audioKeys: ["staging/user/a.wav"],
      videoKeys: [" staging/user/a.mp4 "],
    }),
    {
      image: ["staging/user/a.webp"],
      audio: ["staging/user/a.wav"],
      video: ["staging/user/a.mp4"],
    },
  );
});

Deno.test("scanIngestionManifestChecksum is stable across object-key and session noise", async () => {
  const lhs = await scanIngestionManifestChecksum({
    mediaCounts: {
      image_count: 5,
      audio_count: 1,
      video_count: 1,
      required_video_count: 1,
      video_frame_count: 5,
      video_inference_frame_count: 5,
      has_description: false,
    },
    mediaObjectKeys: {
      image: [" staging/user/frame.webp ", "staging/user/frame.webp"],
      audio: ["staging/user/audio.wav"],
      video: ["staging/user/video.mp4"],
    },
    uploadSessionIds: ["session-b", " session-a ", "session-a"],
  });
  const rhs = await scanIngestionManifestChecksum({
    mediaCounts: {
      has_description: false,
      video_inference_frame_count: 5,
      video_frame_count: 5,
      required_video_count: 1,
      video_count: 1,
      audio_count: 1,
      image_count: 5,
    },
    mediaObjectKeys: {
      image: ["staging/user/frame.webp"],
      audio: ["staging/user/audio.wav"],
      video: ["staging/user/video.mp4"],
    },
    uploadSessionIds: ["session-a", "session-b"],
  });

  assertEquals(lhs, rhs);
  assertEquals(lhs.length, 64);
});

Deno.test("scanIngestionClientState hides last_error until the job is failed", () => {
  assertEquals(
    scanIngestionClientState(jobRow({ last_error: "not for clients" })),
    {
      status: "processing",
      stage: "ai_inference_started",
      attempt_count: 2,
      retry_after: null,
      last_error: null,
    },
  );
});

Deno.test("scanIngestionClientState maps terminal failures to a stable client status", () => {
  assertEquals(
    scanIngestionClientState(
      jobRow({
        status: "failed_terminal",
        stage: "moderation_rejected",
        last_error: "unsafe media",
      }),
    ),
    {
      status: "failed",
      stage: "moderation_rejected",
      attempt_count: 2,
      retry_after: null,
      last_error: "unsafe media",
    },
  );
});

Deno.test("scanIngestionClientState preserves retryable failure metadata", () => {
  assertEquals(
    scanIngestionClientState(
      jobRow({
        status: "failed_retryable",
        stage: "scan_insert_failed",
        retry_after: "2026-07-05T12:05:00.000Z",
        last_error: "insert timeout",
      }),
    ),
    {
      status: "failed_retryable",
      stage: "scan_insert_failed",
      attempt_count: 2,
      retry_after: "2026-07-05T12:05:00.000Z",
      last_error: "insert timeout",
    },
  );
});
