import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import { fetchExportScanBatch } from "./db.ts";
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
        }]),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
});
