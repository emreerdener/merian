import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

import {
  completeScanIngestionFinalization,
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

Deno.test("completeScanIngestionFinalization canonicalizes lifecycle inputs for one RPC", async () => {
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const client = {
    rpc(name: string, arguments_: Record<string, unknown>) {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({ data: "completed", error: null });
    },
  } as unknown as SupabaseClient;

  const result = await completeScanIngestionFinalization(
    {
      scanId: "00000000-0000-4000-8000-000000000091",
      userId: "00000000-0000-4000-8000-000000000092",
      promotedUrlsByStorageKey: new Map([
        ["staging/z.webp", "https://media.merian.app/z.webp"],
        ["staging/a.wav", "https://media.merian.app/a.wav"],
      ]),
      deletedStorageKeys: [" staging/companion.wav ", "staging/companion.wav"],
    },
    client,
  );

  assertEquals(result, "completed");
  assertEquals(rpcName, "complete_scan_ingestion_finalization");
  assertEquals(rpcArguments, {
    p_scan_id: "00000000-0000-4000-8000-000000000091",
    p_user_id: "00000000-0000-4000-8000-000000000092",
    p_promoted_urls_by_storage_key: {
      "staging/a.wav": "https://media.merian.app/a.wav",
      "staging/z.webp": "https://media.merian.app/z.webp",
    },
    p_deleted_storage_keys: ["staging/companion.wav"],
  });
});

Deno.test("completeScanIngestionFinalization persists a supplied response in the completion RPC", async () => {
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const client = {
    rpc(name: string, arguments_: Record<string, unknown>) {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({ data: "already_complete", error: null });
    },
  } as unknown as SupabaseClient;
  const responseEnvelope = {
    success: true,
    data: {
      scan_id: "00000000-0000-4000-8000-000000000091",
    },
  };

  const result = await completeScanIngestionFinalization(
    {
      scanId: "00000000-0000-4000-8000-000000000091",
      userId: "00000000-0000-4000-8000-000000000092",
      promotedUrlsByStorageKey: new Map(),
      deletedStorageKeys: [],
      responseEnvelope,
    },
    client,
  );

  assertEquals(result, "already_complete");
  assertEquals(
    rpcName,
    "complete_scan_ingestion_finalization_with_response",
  );
  assertEquals(rpcArguments, {
    p_scan_id: "00000000-0000-4000-8000-000000000091",
    p_user_id: "00000000-0000-4000-8000-000000000092",
    p_promoted_urls_by_storage_key: {},
    p_deleted_storage_keys: [],
    p_response_envelope: responseEnvelope,
  });
});
