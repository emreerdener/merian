import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  scanIngestionClientState,
  type ScanIngestionJobRow,
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
