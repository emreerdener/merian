import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isScanPersistenceOutcomeUnknown,
  persistOwnedScanRow,
  ScanPersistenceOutcomeUnknownError,
} from "./scanPersistence.ts";

interface VerificationResult {
  data: { id: string } | null;
  error: { message: string } | null;
}

const scanId = "00000000-0000-4000-8000-000000000001";
const userId = "00000000-0000-4000-8000-000000000002";

function verificationClient(
  results: VerificationResult[],
): SupabaseClient {
  let readCount = 0;
  const filters = new Map<string, unknown>();
  return {
    from(table: string) {
      assertEquals(table, "scans");
      return {
        select(columns: string) {
          assertEquals(columns, "id");
          const query = {
            eq(column: string, value: unknown) {
              filters.set(column, value);
              return query;
            },
            maybeSingle() {
              assertEquals(filters.get("id"), scanId);
              assertEquals(filters.get("user_id"), userId);
              const result = results[Math.min(readCount, results.length - 1)];
              readCount += 1;
              return Promise.resolve(result);
            },
          };
          return query;
        },
      };
    },
  } as unknown as SupabaseClient;
}

function persist(
  write: () => Promise<{ error: { message: string } | null }>,
  verificationResults: VerificationResult[],
): Promise<void> {
  return persistOwnedScanRow({
    scanId,
    userId,
    operationName: "testInsert",
    supabaseAdmin: verificationClient(verificationResults),
    write,
    verificationDelaysMs: [0, 0, 0],
  });
}

const ownedRow: VerificationResult = {
  data: { id: scanId },
  error: null,
};
const missingRow: VerificationResult = { data: null, error: null };

Deno.test("persistOwnedScanRow confirms a reported-success write through the exact owner row", async () => {
  await persist(
    () => Promise.resolve({ error: null }),
    [ownedRow],
  );
});

Deno.test("persistOwnedScanRow reconciles a returned write error when an idempotent owner row exists", async () => {
  await persist(
    () => Promise.resolve({ error: { message: "response rejected" } }),
    [ownedRow],
  );
});

Deno.test("persistOwnedScanRow surfaces a definite rejected write only after proving the owner row is absent", async () => {
  const error = await assertRejects(
    () =>
      persist(
        () => Promise.resolve({ error: { message: "constraint failed" } }),
        [missingRow],
      ),
    Error,
    "testInsert: constraint failed",
  );
  assertEquals(isScanPersistenceOutcomeUnknown(error), false);
});

Deno.test("persistOwnedScanRow reconciles a lost write response when a later owner read finds the row", async () => {
  await persist(
    () => Promise.reject(new Error("network timeout")),
    [missingRow, ownedRow],
  );
});

Deno.test("persistOwnedScanRow keeps a lost write response ambiguous when the owner row remains absent", async () => {
  const error = await assertRejects(
    () =>
      persist(
        () => Promise.reject(new Error("network timeout")),
        [missingRow],
      ),
    ScanPersistenceOutcomeUnknownError,
    "scan persistence outcome is unknown",
  );
  assertEquals(isScanPersistenceOutcomeUnknown(error), true);
});

Deno.test("persistOwnedScanRow keeps a reported success ambiguous when exact-owner verification is unavailable", async () => {
  const error = await assertRejects(
    () =>
      persist(
        () => Promise.resolve({ error: null }),
        [{ data: null, error: { message: "read timeout" } }],
      ),
    ScanPersistenceOutcomeUnknownError,
    "testInsert verification: read timeout",
  );
  assertEquals(isScanPersistenceOutcomeUnknown(error), true);
});
