import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  claimScanDeletionJobs,
  getScanDeletionHealth,
  releaseScanDeletionJob,
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

Deno.test("scan deletion claims validate owner-bound leased rows", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const token = "00000000-0000-4000-8000-000000000501";
  const rows = await claimScanDeletionJobs(
    token,
    25,
    client("claim_scan_deletion_jobs", [{
      scan_id: "00000000-0000-4000-8000-000000000101",
      user_id: "00000000-0000-4000-8000-000000000201",
      attempt_count: 1,
    }], calls),
  );
  assertEquals(rows, [{
    scanId: "00000000-0000-4000-8000-000000000101",
    userId: "00000000-0000-4000-8000-000000000201",
    attemptCount: 1,
  }]);
  assertEquals(calls, [{
    p_claim_token: token,
    p_limit: 25,
    p_lease_seconds: 120,
  }]);
});

Deno.test("scan deletion claims fail closed on malformed identities", async () => {
  await assertRejects(
    () =>
      claimScanDeletionJobs(
        "00000000-0000-4000-8000-000000000501",
        25,
        client("claim_scan_deletion_jobs", [{
          scan_id: "not-a-uuid",
          user_id: "00000000-0000-4000-8000-000000000201",
          attempt_count: 1,
        }]),
      ),
    Error,
    "failed validation",
  );
});

Deno.test("scan deletion release is claim-token fenced", async () => {
  const calls: Array<Record<string, unknown>> = [];
  await releaseScanDeletionJob(
    "00000000-0000-4000-8000-000000000101",
    "00000000-0000-4000-8000-000000000201",
    "00000000-0000-4000-8000-000000000501",
    "scan_deletion_failed",
    client("release_scan_deletion_job", true, calls),
  );
  assertEquals(calls, [{
    p_scan_id: "00000000-0000-4000-8000-000000000101",
    p_user_id: "00000000-0000-4000-8000-000000000201",
    p_claim_token: "00000000-0000-4000-8000-000000000501",
    p_error_code: "scan_deletion_failed",
  }]);

  await assertRejects(
    () =>
      releaseScanDeletionJob(
        "00000000-0000-4000-8000-000000000101",
        "00000000-0000-4000-8000-000000000201",
        "00000000-0000-4000-8000-000000000501",
        "scan_deletion_failed",
        client("release_scan_deletion_job", false),
      ),
    Error,
    "Failed to release",
  );
});

Deno.test("scan deletion health validates age consistency", async () => {
  const health = await getScanDeletionHealth(
    client("get_scan_deletion_health", [{
      generated_at: "2026-07-28T06:00:00.000Z",
      pending_count: 2,
      processing_count: 1,
      expired_lease_count: 0,
      oldest_pending_at: "2026-07-28T05:45:00.000Z",
      oldest_pending_age_seconds: 900,
    }]),
  );
  assertEquals(health.pendingCount, 2);
  assertEquals(health.oldestPendingAgeSeconds, 900);

  await assertRejects(
    () =>
      getScanDeletionHealth(
        client("get_scan_deletion_health", [{
          generated_at: "2026-07-28T06:00:00.000Z",
          pending_count: 0,
          processing_count: 0,
          expired_lease_count: 0,
          oldest_pending_at: null,
          oldest_pending_age_seconds: 1,
        }]),
      ),
    Error,
    "inconsistent",
  );
});
