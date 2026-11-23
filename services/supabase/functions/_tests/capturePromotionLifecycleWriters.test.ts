import { assert, assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { updateScanIngestionJob } from "../_shared/scanIngestionJobs.ts";
import { markReplayDispatchFailure } from "../replay-scan-ingestion/db.ts";

// Promotion authorization reads the sealed projection under owner/scan locks,
// without taking a job row lock. These independent lifecycle writers must not
// mutate any projection field or cross into terminal state by a direct UPDATE.
Deno.test("unfenced ingestion updates preserve the promotion projection and terminal fence", async () => {
  const writes: { table: string; values: Record<string, unknown> }[] = [];
  const rpcs: string[] = [];
  const client = {
    rpc(name: string) {
      rpcs.push(name);
      return Promise.resolve({ error: null });
    },
    from(table: string) {
      return {
        update(values: Record<string, unknown>) {
          writes.push({ table, values });
          const query = {
            eq() {
              return query;
            },
            not() {
              return query;
            },
            then(resolve: (value: { error: null }) => void) {
              resolve({ error: null });
            },
          };
          return query;
        },
      };
    },
  } as unknown as SupabaseClient;
  const identity = {
    scanId: "00000000-0000-4000-8000-000000000091",
    userId: "00000000-0000-4000-8000-000000000092",
  };
  const allowedStatuses = [
    "processing",
    "finalizing",
    "retrying",
    "failed_retryable",
  ] as const;
  for (const status of [...allowedStatuses, "failed_terminal"] as const) {
    await updateScanIngestionJob(
      { ...identity, status, stage: "synthetic" },
      client,
    );
  }
  for (const terminal of [false, true]) {
    await markReplayDispatchFailure({
      ...identity,
      stage: "synthetic",
      errorMessage: "synthetic failure",
      retryAfterIso: null,
      terminal,
    }, client);
  }
  const jobFields = new Set([
    "status",
    "stage",
    "last_error",
    "retry_after",
    "completed_at",
    "updated_at",
    "terminal_reason_code",
    "locked_at",
    "lock_expires_at",
  ]);
  const intentFields = new Set(["last_replay_error", "updated_at"]);
  assertEquals(writes.length, 7);
  for (const { table, values } of writes) {
    assert(
      table === "scan_ingestion_jobs" || table === "scan_ingestion_intents",
    );
    const allowed = table === "scan_ingestion_jobs" ? jobFields : intentFields;
    assert(
      Object.keys(values).every((key) => allowed.has(key)),
      "sealed projection changed",
    );
    if (table === "scan_ingestion_jobs") {
      assert(allowedStatuses.some((status) => status === values.status));
    }
  }
  assertEquals(rpcs, [
    "fail_scan_ingestion_terminal",
    "fail_scan_ingestion_terminal",
  ]);
});
