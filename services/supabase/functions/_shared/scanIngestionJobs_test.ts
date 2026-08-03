import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";

import {
  completeScanIngestionFinalization,
  recoverStrandedScanIngestionAttempt,
  scanIngestionClientState,
  type ScanIngestionJobRow,
  scanIngestionManifestChecksum,
  scanIngestionMediaObjectKeys,
  updateScanIngestionJob,
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

Deno.test("updateScanIngestionJob settles terminal failures only through the entitlement orchestrator", async () => {
  let directUpdateAttempted = false;
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const client = {
    rpc(name: string, arguments_: Record<string, unknown>) {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({
        data: { result: "failed_terminal" },
        error: null,
      });
    },
    from() {
      directUpdateAttempted = true;
      throw new Error("terminal state must not use a direct table update");
    },
  } as unknown as SupabaseClient;

  await updateScanIngestionJob(
    {
      scanId: "00000000-0000-4000-8000-000000000091",
      userId: "00000000-0000-4000-8000-000000000092",
      status: "failed_terminal",
      stage: "moderation_rejected",
      lastError: " unsafe media ",
      terminalReasonCode: "policy_rejected",
    },
    client,
  );

  assertEquals(rpcName, "fail_scan_ingestion_terminal");
  assertEquals(rpcArguments, {
    p_scan_id: "00000000-0000-4000-8000-000000000091",
    p_user_id: "00000000-0000-4000-8000-000000000092",
    p_stage: "moderation_rejected",
    p_last_error: " unsafe media ",
    p_terminal_reason_code: "policy_rejected",
  });
  assertEquals(directUpdateAttempted, false);
});

Deno.test("updateScanIngestionJob fails closed when terminal settlement is unavailable", async () => {
  let directUpdateAttempted = false;
  const client = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "PGRST202",
          message:
            "Could not find fail_scan_ingestion_terminal in the schema cache",
        },
      });
    },
    from() {
      directUpdateAttempted = true;
      throw new Error("terminal state must not use a direct table update");
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      updateScanIngestionJob(
        {
          scanId: "00000000-0000-4000-8000-000000000091",
          userId: "00000000-0000-4000-8000-000000000092",
          status: "failed_terminal",
          stage: "provider_failed",
          lastError: "terminal provider failure",
        },
        client,
      ),
    Error,
    "fail_scan_ingestion_terminal",
  );
  assertEquals(directUpdateAttempted, false);
});

Deno.test("completeScanIngestionFinalization canonicalizes lifecycle inputs for one RPC", async () => {
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const client = {
    rpc(name: string, arguments_: Record<string, unknown>) {
      rpcName = name;
      rpcArguments = arguments_;
      return Promise.resolve({
        data: { result: "completed", response_envelope: null },
        error: null,
      });
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

  assertEquals(result, { result: "completed", responseEnvelope: null });
  assertEquals(rpcName, "complete_scan_ingestion_with_entitlement");
  assertEquals(rpcArguments, {
    p_scan_id: "00000000-0000-4000-8000-000000000091",
    p_user_id: "00000000-0000-4000-8000-000000000092",
    p_response_envelope: null,
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
      return Promise.resolve({
        data: {
          result: "already_complete",
          response_envelope: responseEnvelope,
        },
        error: null,
      });
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

  assertEquals(result, {
    result: "already_complete",
    responseEnvelope,
  });
  assertEquals(rpcName, "complete_scan_ingestion_with_entitlement");
  assertEquals(rpcArguments, {
    p_scan_id: "00000000-0000-4000-8000-000000000091",
    p_user_id: "00000000-0000-4000-8000-000000000092",
    p_promoted_urls_by_storage_key: {},
    p_deleted_storage_keys: [],
    p_response_envelope: responseEnvelope,
  });
});

Deno.test("completeScanIngestionFinalization falls back only when the additive response RPC is unavailable", async () => {
  const rpcNames: string[] = [];
  const client = {
    rpc(name: string) {
      rpcNames.push(name);
      return Promise.resolve(
        name === "complete_scan_ingestion_with_entitlement"
          ? {
            data: null,
            error: {
              code: "PGRST202",
              message: "Could not find the function in the schema cache",
            },
          }
          : { data: "completed", error: null },
      );
    },
  } as unknown as SupabaseClient;

  const result = await completeScanIngestionFinalization(
    {
      scanId: "00000000-0000-4000-8000-000000000091",
      userId: "00000000-0000-4000-8000-000000000092",
      promotedUrlsByStorageKey: new Map(),
      deletedStorageKeys: [],
      responseEnvelope: {
        success: true,
        data: { scan_id: "00000000-0000-4000-8000-000000000091" },
      },
    },
    client,
  );

  assertEquals(result.result, "completed");
  assertEquals(rpcNames, [
    "complete_scan_ingestion_with_entitlement",
    "complete_scan_ingestion_finalization_with_response",
  ]);
});

Deno.test("completeScanIngestionFinalization never masks an internal undefined-function error", async () => {
  const rpcNames: string[] = [];
  const client = {
    rpc(name: string) {
      rpcNames.push(name);
      return Promise.resolve({
        data: null,
        error: {
          code: "42883",
          message:
            "function internal.refresh_required_media(uuid) does not exist",
        },
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      completeScanIngestionFinalization(
        {
          scanId: "00000000-0000-4000-8000-000000000091",
          userId: "00000000-0000-4000-8000-000000000092",
          promotedUrlsByStorageKey: new Map(),
          deletedStorageKeys: [],
          responseEnvelope: {
            success: true,
            data: { scan_id: "00000000-0000-4000-8000-000000000091" },
          },
        },
        client,
      ),
    Error,
    "refresh_required_media",
  );
  assertEquals(rpcNames, [
    "complete_scan_ingestion_with_entitlement",
  ]);
});

Deno.test("recoverStrandedScanIngestionAttempt parses exact recovery evidence", async () => {
  const scanId = "00000000-0000-4000-8000-000000000091";
  const userId = "00000000-0000-4000-8000-000000000092";
  const sourceId = "00000000-0000-4000-8000-000000000093";
  let observedName = "";
  let observedArguments: Record<string, unknown> = {};
  const client = {
    rpc(name: string, arguments_: Record<string, unknown>) {
      observedName = name;
      observedArguments = arguments_;
      return Promise.resolve({
        data: {
          outcome: "media_restage_required",
          authorized_source_user_id: sourceId,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  assertEquals(
    await recoverStrandedScanIngestionAttempt(scanId, userId, client),
    {
      outcome: "media_restage_required",
      authorizedSourceUserId: sourceId,
    },
  );
  assertEquals(observedName, "recover_stranded_scan_ingestion_attempt");
  assertEquals(observedArguments, {
    p_scan_id: scanId,
    p_user_id: userId,
  });
});

Deno.test("recoverStrandedScanIngestionAttempt tolerates only a missing rollout routine", async () => {
  const missingClient = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "PGRST202",
          message: "routine is absent from the schema cache",
        },
      });
    },
  } as unknown as SupabaseClient;
  assertEquals(
    await recoverStrandedScanIngestionAttempt(
      "00000000-0000-4000-8000-000000000091",
      "00000000-0000-4000-8000-000000000092",
      missingClient,
    ),
    null,
  );

  const brokenClient = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "42883",
          message:
            "function internal.unrelated_dependency(uuid) does not exist",
        },
      });
    },
  } as unknown as SupabaseClient;
  await assertRejects(
    () =>
      recoverStrandedScanIngestionAttempt(
        "00000000-0000-4000-8000-000000000091",
        "00000000-0000-4000-8000-000000000092",
        brokenClient,
      ),
    Error,
    "unrelated_dependency",
  );
});

Deno.test("recoverStrandedScanIngestionAttempt rejects malformed authority", async () => {
  const client = {
    rpc() {
      return Promise.resolve({
        data: {
          outcome: "media_restage_required",
          authorized_source_user_id: "../../another-user",
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      recoverStrandedScanIngestionAttempt(
        "00000000-0000-4000-8000-000000000091",
        "00000000-0000-4000-8000-000000000092",
        client,
      ),
    Error,
    "malformed RPC response",
  );
});
