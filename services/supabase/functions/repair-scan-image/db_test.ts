import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  isScanImageRepairPersistenceOutcomeUnknown,
  persistOwnedScanImageRepair,
  resolveScanImageRepairPersistence,
  ScanImageRepairPersistenceOutcomeUnknownError,
} from "./db.ts";

const userId = "4c600000-0000-4000-8000-000000000001";
const sourceUrl =
  `https://media.merian.app/public_uploads/free/${userId}/old.webp`;
const replacementUrl =
  `https://media.merian.app/public_uploads/pro/${userId}/new.webp`;

interface RepairDatabaseMockOptions {
  rpcResult?:
    | { data: unknown; error: { message: string } | null }
    | Error;
  sourceReferenced?: boolean;
  replacementReferenced?: boolean;
  readError?: { message: string } | null;
}

function repairDatabaseMock(
  options: RepairDatabaseMockOptions,
): { client: SupabaseClient; referenceReads: string[] } {
  const referenceReads: string[] = [];
  const client = {
    rpc(name: string) {
      assertEquals(name, "repair_owned_scan_image_reference");
      const result = options.rpcResult ??
        {
          data: {
            updated_scan_count: 2,
            updated_post_media_count: 1,
          },
          error: null,
        };
      if (result instanceof Error) return Promise.reject(result);
      return Promise.resolve(result);
    },
    from(table: string) {
      assertEquals(table, "scans");
      let inspectedUrl = "";
      const query = {
        select() {
          return query;
        },
        eq() {
          return query;
        },
        contains(column: string, values: string[]) {
          assertEquals(column, "image_storage_urls");
          inspectedUrl = values[0] ?? "";
          referenceReads.push(inspectedUrl);
          return query;
        },
        limit() {
          const referenced = inspectedUrl === sourceUrl
            ? options.sourceReferenced ?? false
            : options.replacementReferenced ?? false;
          return Promise.resolve({
            data: referenced ? [{ id: "scan-id" }] : [],
            error: options.readError ?? null,
          });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  return { client, referenceReads };
}

Deno.test("scan image repair persistence returns a valid direct RPC result without rereading", async () => {
  const mock = repairDatabaseMock({});
  assertEquals(
    await persistOwnedScanImageRepair(
      userId,
      sourceUrl,
      replacementUrl,
      mock.client,
    ),
    {
      updatedScanCount: 2,
      updatedPostMediaCount: 1,
    },
  );
  assertEquals(mock.referenceReads, []);
});

Deno.test("scan image repair persistence reconciles a lost RPC response from exact owner references", async () => {
  const mock = repairDatabaseMock({
    rpcResult: new Error("network timeout"),
    sourceReferenced: false,
    replacementReferenced: true,
  });
  assertEquals(
    await persistOwnedScanImageRepair(
      userId,
      sourceUrl,
      replacementUrl,
      mock.client,
    ),
    {
      updatedScanCount: 1,
      updatedPostMediaCount: 0,
    },
  );
  assertEquals(mock.referenceReads, [sourceUrl, replacementUrl]);
});

Deno.test("scan image repair persistence permits rollback only after a returned rejection proves the replacement unreferenced", async () => {
  const mock = repairDatabaseMock({
    rpcResult: { data: null, error: { message: "transaction rejected" } },
    sourceReferenced: true,
    replacementReferenced: false,
  });
  const error = await assertRejects(
    () =>
      persistOwnedScanImageRepair(
        userId,
        sourceUrl,
        replacementUrl,
        mock.client,
      ),
    Error,
    "transaction rejected",
  );
  assertEquals(isScanImageRepairPersistenceOutcomeUnknown(error), false);
});

Deno.test("scan image repair persistence remains ambiguous when both source and replacement are referenced", async () => {
  const mock = repairDatabaseMock({
    rpcResult: new Error("network timeout"),
    sourceReferenced: true,
    replacementReferenced: true,
  });
  const error = await assertRejects(
    () =>
      persistOwnedScanImageRepair(
        userId,
        sourceUrl,
        replacementUrl,
        mock.client,
      ),
    ScanImageRepairPersistenceOutcomeUnknownError,
    "Could not confirm",
  );
  assertEquals(isScanImageRepairPersistenceOutcomeUnknown(error), true);
});

Deno.test("scan image repair persistence remains ambiguous when owner verification is unavailable", async () => {
  const mock = repairDatabaseMock({
    rpcResult: { data: null, error: { message: "transaction rejected" } },
    readError: { message: "read unavailable" },
  });
  const error = await assertRejects(
    () =>
      persistOwnedScanImageRepair(
        userId,
        sourceUrl,
        replacementUrl,
        mock.client,
      ),
    ScanImageRepairPersistenceOutcomeUnknownError,
    "Could not verify",
  );
  assertEquals(isScanImageRepairPersistenceOutcomeUnknown(error), true);
});

Deno.test("scan image repair rollback topology is fail-closed", () => {
  assertEquals(
    resolveScanImageRepairPersistence("reported_rejected", true, false),
    "rejected",
  );
  assertEquals(
    resolveScanImageRepairPersistence("unknown", true, false),
    "unknown",
  );
  assertEquals(
    resolveScanImageRepairPersistence("reported_rejected", true, true),
    "unknown",
  );
  assertEquals(
    resolveScanImageRepairPersistence("unknown", false, true),
    "committed",
  );
});
