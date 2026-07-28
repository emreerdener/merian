import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import {
  advanceExportJobStep,
  checkExportSourceFence,
  completePreparedExportJob,
  fetchDueExportJobIds,
  fetchExportJobChunks,
  fetchExportQueueHealth,
  fetchExportScanBatch,
  stagePreparedExportArchive,
} from "./db.ts";
import {
  MAXIMUM_DWCA_IMAGE_URL_BYTES,
  MAXIMUM_DWCA_IMAGE_URLS,
  MAXIMUM_EXPORT_SOURCE_PAGE_BYTES,
} from "./limits.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

const job: ClaimedExportJob = {
  id: "00000000-0000-4000-8000-000000000201",
  userId: "00000000-0000-4000-8000-000000000202",
  exportScope: "personal",
  includePreciseCoordinates: false,
  pseudonymKeyVersion: 1,
  maxExportRows: 5_000,
  maxArchiveBytes: 8 * 1024 * 1024,
  archiveObjectKey: null,
  fileUrl: null,
  archiveReadyAt: null,
  attemptCount: 1,
  leaseExpiresAt: "2026-07-25T23:59:00.000Z",
  workPhase: "occurrence",
  occurrenceAfterId: null,
  multimediaAfterId: null,
  occurrenceRows: 0,
  multimediaRows: 0,
  csvBytes: 0,
  chunkSequence: 0,
};

Deno.test("advanceExportJobStep persists bounded chunk CRC metadata", async () => {
  const calls: Array<{
    name: string;
    arguments: Record<string, unknown>;
  }> = [];
  const claimToken = "00000000-0000-4000-8000-000000000401";
  const objectKey =
    `exports/${job.userId}/${job.id}/work/occurrence/00000000-${claimToken}.csv`;
  const result = await advanceExportJobStep(
    job,
    claimToken,
    "occurrence",
    "00000000-0000-4000-8000-000000000301",
    1,
    objectKey,
    3,
    1_439_417_003,
    true,
    mockClient("multimedia", calls),
  );

  assertEquals(result, "multimedia");
  assertEquals(calls, [{
    name: "advance_export_job_step",
    arguments: {
      p_job_id: job.id,
      p_claim_token: claimToken,
      p_expected_phase: "occurrence",
      p_next_after_id: "00000000-0000-4000-8000-000000000301",
      p_row_count: 1,
      p_chunk_object_key: objectKey,
      p_chunk_byte_count: 3,
      p_chunk_crc32: 1_439_417_003,
      p_page_complete: true,
    },
  }]);
});

Deno.test("fetchExportJobChunks validates durable CRC and sequence metadata", async () => {
  const manifest = await fetchExportJobChunks(
    job.id,
    "00000000-0000-4000-8000-000000000401",
    mockClient([{
      chunk_phase: "occurrence",
      chunk_sequence: 0,
      object_key: "exports/test/work/occurrence/00000000.csv",
      byte_count: 3,
      crc32: 1_439_417_003,
    }]),
  );

  assertEquals(manifest, [{
    phase: "occurrence",
    sequence: 0,
    objectKey: "exports/test/work/occurrence/00000000.csv",
    byteCount: 3,
    crc32: 1_439_417_003,
  }]);

  await assertRejects(
    () =>
      fetchExportJobChunks(
        job.id,
        "00000000-0000-4000-8000-000000000401",
        mockClient([{
          chunk_phase: "occurrence",
          chunk_sequence: 0,
          object_key: "exports/test/work/occurrence/00000000.csv",
          byte_count: 3,
          crc32: 0x1_0000_0000,
        }]),
      ),
    ExportWorkerError,
    "malformed",
  );

  await assertRejects(
    () =>
      fetchExportJobChunks(
        job.id,
        "00000000-0000-4000-8000-000000000401",
        mockClient([{
          chunk_phase: "occurrence",
          chunk_sequence: 0,
          object_key: "exports/test/work/occurrence/00000000.csv",
          byte_count: 0,
          crc32: 1,
        }]),
      ),
    ExportWorkerError,
    "malformed",
  );
});

Deno.test("checkExportSourceFence validates the full-set fence status", async () => {
  const calls: Array<{
    name: string;
    arguments: Record<string, unknown>;
  }> = [];
  await checkExportSourceFence(
    job.id,
    "00000000-0000-4000-8000-000000000401",
    "assembling",
    mockClient("current", calls),
  );
  assertEquals(calls, [{
    name: "check_dwca_export_source_fence",
    arguments: {
      p_job_id: job.id,
      p_claim_token: "00000000-0000-4000-8000-000000000401",
      p_expected_phase: "assembling",
    },
  }]);

  const error = await assertRejects(
    () =>
      checkExportSourceFence(
        job.id,
        "00000000-0000-4000-8000-000000000401",
        "delivering",
        mockClient("source_snapshot_changed"),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
});

Deno.test("stage and completion map transactional privacy rejection to a terminal source change", async () => {
  const rejectedClient = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "55001",
          message: "dwca_export_source_snapshot_changed",
        },
      });
    },
  } as unknown as SupabaseClient;

  for (
    const operation of [
      () =>
        stagePreparedExportArchive(
          job.id,
          "00000000-0000-4000-8000-000000000401",
          `exports/${job.userId}/${job.id}/attempt.zip`,
          "https://r2.example.invalid/export.zip",
          rejectedClient,
        ),
      () =>
        completePreparedExportJob(
          job.id,
          "00000000-0000-4000-8000-000000000401",
          rejectedClient,
        ),
    ]
  ) {
    const error = await assertRejects(operation, ExportWorkerError);
    assertEquals(error.code, "source_snapshot_changed");
  }
});

function mockClient(
  data: unknown,
  calls: Array<{ name: string; arguments: Record<string, unknown> }> = [],
): SupabaseClient {
  return {
    rpc(name: string, rpcArguments: Record<string, unknown>) {
      calls.push({ name, arguments: rpcArguments });
      return Promise.resolve({ data, error: null });
    },
  } as unknown as SupabaseClient;
}

Deno.test("fetchExportScanBatch uses the fenced byte-aware RPC", async () => {
  const calls: Array<{
    name: string;
    arguments: Record<string, unknown>;
  }> = [];
  const scanId = "00000000-0000-4000-8000-000000000301";
  const result = await fetchExportScanBatch(
    job,
    "00000000-0000-4000-8000-000000000401",
    "occurrence",
    null,
    mockClient([
      {
        scan_id: scanId,
        scan_payload: {
          id: scanId,
          user_id: job.userId,
          ecological_interactions: ["pollinating milkweed"],
          sex: null,
          species_dictionary: null,
        },
        source_byte_count: 256,
        page_complete: false,
        source_row_oversize: false,
        source_revision_changed: false,
      },
    ], calls),
  );

  assertEquals(result, {
    scans: [{
      id: scanId,
      user_id: job.userId,
      ecological_interactions: ["pollinating milkweed"],
      sex: null,
      species_dictionary: null,
    }],
    sourceByteCount: 256,
    pageComplete: false,
  });
  assertEquals(calls, [{
    name: "get_dwca_export_scan_batch",
    arguments: {
      p_job_id: job.id,
      p_claim_token: "00000000-0000-4000-8000-000000000401",
      p_expected_phase: "occurrence",
      p_after_id: null,
      p_max_rows: 100,
      p_max_source_bytes: MAXIMUM_EXPORT_SOURCE_PAGE_BYTES,
    },
  }]);
});

Deno.test("fetchExportScanBatch recognizes the completion sentinel", async () => {
  const result = await fetchExportScanBatch(
    job,
    "00000000-0000-4000-8000-000000000401",
    "multimedia",
    null,
    mockClient([{
      scan_id: null,
      scan_payload: null,
      source_byte_count: 0,
      page_complete: true,
      source_row_oversize: false,
      source_revision_changed: false,
    }]),
  );

  assertEquals(result, {
    scans: [],
    sourceByteCount: 0,
    pageComplete: true,
  });
});

Deno.test("fetchExportScanBatch rejects an oversized source sentinel", async () => {
  const error = await assertRejects(
    () =>
      fetchExportScanBatch(
        job,
        "00000000-0000-4000-8000-000000000401",
        "multimedia",
        null,
        mockClient([{
          scan_id: null,
          scan_payload: null,
          source_byte_count: MAXIMUM_EXPORT_SOURCE_PAGE_BYTES + 1,
          page_complete: false,
          source_row_oversize: true,
          source_revision_changed: false,
        }]),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "export_too_large");
});

Deno.test("fetchExportScanBatch rejects arrays beyond database bounds", async () => {
  const scanId = "00000000-0000-4000-8000-000000000301";
  const error = await assertRejects(
    () =>
      fetchExportScanBatch(
        job,
        "00000000-0000-4000-8000-000000000401",
        "multimedia",
        null,
        mockClient([{
          scan_id: scanId,
          scan_payload: {
            id: scanId,
            user_id: job.userId,
            image_storage_urls: Array.from(
              { length: MAXIMUM_DWCA_IMAGE_URLS + 1 },
              (_, index) => `https://media.example.invalid/${index}.webp`,
            ),
          },
          source_byte_count: 1_024,
          page_complete: true,
          source_row_oversize: false,
          source_revision_changed: false,
        }]),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
});

Deno.test("fetchExportScanBatch enforces element bounds in UTF-8 bytes", async () => {
  const scanId = "00000000-0000-4000-8000-000000000301";
  const error = await assertRejects(
    () =>
      fetchExportScanBatch(
        job,
        "00000000-0000-4000-8000-000000000401",
        "multimedia",
        null,
        mockClient([{
          scan_id: scanId,
          scan_payload: {
            id: scanId,
            user_id: job.userId,
            image_storage_urls: [
              "é".repeat(Math.floor(MAXIMUM_DWCA_IMAGE_URL_BYTES / 2) + 1),
            ],
          },
          source_byte_count: 8_192,
          page_complete: true,
          source_row_oversize: false,
          source_revision_changed: false,
        }]),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
});

Deno.test("fetchExportScanBatch rejects a changed source revision terminally", async () => {
  const error = await assertRejects(
    () =>
      fetchExportScanBatch(
        job,
        "00000000-0000-4000-8000-000000000401",
        "multimedia",
        null,
        mockClient([{
          scan_id: null,
          scan_payload: null,
          source_byte_count: 0,
          page_complete: false,
          source_row_oversize: false,
          source_revision_changed: true,
        }]),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
});

Deno.test("fetchDueExportJobIds validates the bounded discovery batch", async () => {
  const calls: Array<{
    name: string;
    arguments: Record<string, unknown>;
  }> = [];
  const firstJobId = "00000000-0000-4000-8000-000000000501";
  const secondJobId = "00000000-0000-4000-8000-000000000502";
  const result = await fetchDueExportJobIds(
    mockClient([
      { job_id: firstJobId },
      { job_id: secondJobId },
    ], calls),
    5,
  );

  assertEquals(result, [firstJobId, secondJobId]);
  assertEquals(calls, [{
    name: "get_due_export_job_ids",
    arguments: { p_limit: 5 },
  }]);
  await assertRejects(
    () => fetchDueExportJobIds(mockClient([]), 6),
    ExportWorkerError,
    "limit is invalid",
  );
});

Deno.test("fetchExportQueueHealth validates one consistent telemetry row", async () => {
  const result = await fetchExportQueueHealth(mockClient([{
    generated_at: "2026-07-26T22:00:00.000Z",
    backlog_count: 7,
    due_count: 5,
    active_claim_count: 2,
    expired_claim_count: 1,
    oldest_due_at: "2026-07-26T21:55:00.000Z",
    oldest_due_age_seconds: 300,
  }]));

  assertEquals(result, {
    generatedAt: "2026-07-26T22:00:00.000Z",
    backlogCount: 7,
    dueCount: 5,
    activeClaimCount: 2,
    expiredClaimCount: 1,
    oldestDueAt: "2026-07-26T21:55:00.000Z",
    oldestDueAgeSeconds: 300,
  });
});

Deno.test("fetchExportQueueHealth rejects inconsistent telemetry", async () => {
  await assertRejects(
    () =>
      fetchExportQueueHealth(mockClient([{
        generated_at: "2026-07-26T22:00:00.000Z",
        backlog_count: 0,
        due_count: 1,
        active_claim_count: 0,
        expired_claim_count: 0,
        oldest_due_at: null,
        oldest_due_age_seconds: null,
      }])),
    ExportWorkerError,
    "inconsistent state",
  );
});
