import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  claimDwcaArchiveCleanupJobs,
  getDwcaArchiveCleanupHealth,
} from "./db.ts";

function client(
  expectedName: string,
  data: unknown,
  calls: Array<Record<string, unknown>> = [],
): SupabaseClient {
  return {
    rpc(name: string, args?: Record<string, unknown>) {
      assertEquals(name, expectedName);
      calls.push(args ?? {});
      return Promise.resolve({ data, error: null });
    },
  } as unknown as SupabaseClient;
}

Deno.test("cleanup claims validate leased archive rows", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const token = "00000000-0000-4000-8000-000000000501";
  const rows = await claimDwcaArchiveCleanupJobs(
    token,
    25,
    client("claim_dwca_archive_cleanup_jobs", [{
      cleanup_id: "00000000-0000-4000-8000-000000000101",
      job_id: "00000000-0000-4000-8000-000000000201",
      object_key:
        "exports/00000000-0000-4000-8000-000000000301/00000000-0000-4000-8000-000000000201/00000000-0000-4000-8000-000000000401.zip",
      attempt_count: 1,
    }], calls),
  );
  assertEquals(rows.length, 1);
  assertEquals(calls, [{
    p_claim_token: token,
    p_limit: 25,
    p_lease_seconds: 120,
  }]);
});

Deno.test("cleanup claims fail closed on nonarchive object keys", async () => {
  await assertRejects(
    () =>
      claimDwcaArchiveCleanupJobs(
        "00000000-0000-4000-8000-000000000501",
        25,
        client("claim_dwca_archive_cleanup_jobs", [{
          cleanup_id: "00000000-0000-4000-8000-000000000101",
          job_id: null,
          object_key: "exports/user/job/work/chunk.csv",
          attempt_count: 1,
        }]),
      ),
    Error,
    "failed validation",
  );
});

Deno.test("cleanup health validates counts and due-age consistency", async () => {
  const health = await getDwcaArchiveCleanupHealth(
    client("get_dwca_archive_cleanup_health", [{
      generated_at: "2026-07-28T04:00:00.000Z",
      pending_count: 2,
      processing_count: 1,
      expired_lease_count: 0,
      oldest_due_at: "2026-07-28T03:45:00.000Z",
      oldest_due_age_seconds: 900,
    }]),
  );
  assertEquals(health.pendingCount, 2);
  assertEquals(health.oldestDueAgeSeconds, 900);

  await assertRejects(
    () =>
      getDwcaArchiveCleanupHealth(
        client("get_dwca_archive_cleanup_health", [{
          generated_at: "2026-07-28T04:00:00.000Z",
          pending_count: 0,
          processing_count: 0,
          expired_lease_count: 0,
          oldest_due_at: null,
          oldest_due_age_seconds: 10,
        }]),
      ),
    Error,
    "inconsistent",
  );
});
