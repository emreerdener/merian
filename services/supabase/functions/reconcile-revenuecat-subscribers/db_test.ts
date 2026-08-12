import { assertEquals, assertRejects } from "@std/assert";
import { SupabaseClient } from "@supabase/supabase-js";
import {
  claimRevenueCatReconciliationForUser,
  claimRevenueCatReconciliations,
  getRevenueCatReconciliationHealth,
  RevenueCatReconciliationDatabaseError,
} from "./db.ts";

function mockClient(
  data: unknown,
  calls: Array<{ name: string; arguments?: Record<string, unknown> }> = [],
): SupabaseClient {
  return {
    rpc(name: string, rpcArguments?: Record<string, unknown>) {
      calls.push({ name, arguments: rpcArguments });
      return Promise.resolve({ data, error: null });
    },
  } as unknown as SupabaseClient;
}

Deno.test("claimRevenueCatReconciliations requests and validates one bounded wave", async () => {
  const calls: Array<{
    name: string;
    arguments?: Record<string, unknown>;
  }> = [];
  const data = [{
    user_id: "00000000-0000-4000-8000-000000000001",
    lookup_app_user_id: "revenuecat-customer",
    claim_token: "00000000-0000-4001-8000-000000000001",
    claim_expires_at: "2026-07-26T04:00:00.000Z",
    allow_non_subscription_pass_grant: false,
  }];

  assertEquals(
    await claimRevenueCatReconciliations(mockClient(data, calls), 6),
    [{
      userId: data[0].user_id,
      lookupAppUserId: data[0].lookup_app_user_id,
      claimToken: data[0].claim_token,
      claimExpiresAt: data[0].claim_expires_at,
      allowNonSubscriptionPassGrant: false,
    }],
  );
  assertEquals(calls, [{
    name: "claim_revenuecat_reconciliations",
    arguments: { p_limit: 6 },
  }]);
});

Deno.test("claimRevenueCatReconciliations rejects invalid and oversized waves", async () => {
  await assertRejects(
    () => claimRevenueCatReconciliations(mockClient([]), 0),
    RevenueCatReconciliationDatabaseError,
    "invalid limit",
  );
  await assertRejects(
    () =>
      claimRevenueCatReconciliations(
        mockClient(Array.from({ length: 7 }, () => ({}))),
        6,
      ),
    RevenueCatReconciliationDatabaseError,
    "exceeded its requested limit",
  );
});

Deno.test("claimRevenueCatReconciliationForUser validates the exact lease", async () => {
  const calls: Array<{
    name: string;
    arguments?: Record<string, unknown>;
  }> = [];
  const userId = "00000000-0000-4000-8000-000000000001";
  const row = {
    user_id: userId,
    lookup_app_user_id: userId.toUpperCase(),
    claim_token: "00000000-0000-4001-8000-000000000001",
    claim_expires_at: "2026-07-26T04:00:00.000Z",
    allow_non_subscription_pass_grant: true,
  };

  assertEquals(
    await claimRevenueCatReconciliationForUser(
      mockClient([row], calls),
      userId,
    ),
    {
      userId,
      lookupAppUserId: row.lookup_app_user_id,
      claimToken: row.claim_token,
      claimExpiresAt: row.claim_expires_at,
      allowNonSubscriptionPassGrant: true,
    },
  );
  assertEquals(calls, [{
    name: "claim_revenuecat_reconciliation_for_user",
    arguments: { p_user_id: userId },
  }]);
});

Deno.test("claimRevenueCatReconciliationForUser rejects no or wrong lease", async () => {
  const userId = "00000000-0000-4000-8000-000000000001";
  await assertRejects(
    () => claimRevenueCatReconciliationForUser(mockClient([]), userId),
    RevenueCatReconciliationDatabaseError,
    "was unavailable",
  );
  await assertRejects(
    () =>
      claimRevenueCatReconciliationForUser(
        mockClient([{
          user_id: "00000000-0000-4000-8000-000000000002",
          lookup_app_user_id: "customer",
          claim_token: "00000000-0000-4001-8000-000000000001",
          claim_expires_at: "2026-07-26T04:00:00.000Z",
          allow_non_subscription_pass_grant: true,
        }]),
        userId,
      ),
    RevenueCatReconciliationDatabaseError,
    "wrong user",
  );
});

Deno.test("getRevenueCatReconciliationHealth validates backlog telemetry", async () => {
  const calls: Array<{
    name: string;
    arguments?: Record<string, unknown>;
  }> = [];
  const health = await getRevenueCatReconciliationHealth(
    mockClient([{
      generated_at: "2026-07-26T03:30:00.000Z",
      due_count: 12,
      expired_claim_count: 1,
      oldest_due_at: "2026-07-26T02:45:00.000Z",
      oldest_due_age_seconds: 2_700,
      signout_prepared_count: 2,
      signout_bound_count: 1,
      oldest_signout_pending_at: "2026-07-26T03:00:00.000Z",
      oldest_signout_pending_age_seconds: 1_800,
    }], calls),
  );

  assertEquals(health, {
    generatedAt: "2026-07-26T03:30:00.000Z",
    dueCount: 12,
    expiredClaimCount: 1,
    oldestDueAt: "2026-07-26T02:45:00.000Z",
    oldestDueAgeSeconds: 2_700,
    signoutPreparedCount: 2,
    signoutBoundCount: 1,
    oldestSignoutPendingAt: "2026-07-26T03:00:00.000Z",
    oldestSignoutPendingAgeSeconds: 1_800,
  });
  assertEquals(calls, [{
    name: "get_revenuecat_reconciliation_health",
    arguments: undefined,
  }]);

  const legacy = await getRevenueCatReconciliationHealth(
    mockClient([{
      generated_at: "2026-07-26T03:30:00.000Z",
      due_count: 0,
      expired_claim_count: 0,
      oldest_due_at: null,
      oldest_due_age_seconds: null,
    }]),
  );
  assertEquals(legacy.signoutPreparedCount, 0);
  assertEquals(legacy.signoutBoundCount, 0);
});

Deno.test("getRevenueCatReconciliationHealth rejects inconsistent telemetry", async () => {
  await assertRejects(
    () =>
      getRevenueCatReconciliationHealth(
        mockClient([{
          generated_at: "2026-07-26T03:30:00.000Z",
          due_count: 0,
          expired_claim_count: 0,
          oldest_due_at: "2026-07-26T02:45:00.000Z",
          oldest_due_age_seconds: 2_700,
        }]),
      ),
    RevenueCatReconciliationDatabaseError,
    "inconsistent backlog state",
  );
  await assertRejects(
    () =>
      getRevenueCatReconciliationHealth(
        mockClient([{
          generated_at: "2026-07-26T03:30:00.000Z",
          due_count: 0,
          expired_claim_count: 0,
          oldest_due_at: null,
          oldest_due_age_seconds: null,
          signout_prepared_count: 0,
          signout_bound_count: 1,
          oldest_signout_pending_at: null,
          oldest_signout_pending_age_seconds: null,
        }]),
      ),
    RevenueCatReconciliationDatabaseError,
    "inconsistent backlog state",
  );
  await assertRejects(
    () =>
      getRevenueCatReconciliationHealth(
        mockClient([{
          generated_at: "not-a-timestamp",
          due_count: 1,
          expired_claim_count: 0,
          oldest_due_at: "2026-07-26T02:45:00.000Z",
          oldest_due_age_seconds: 2_700,
        }]),
      ),
    RevenueCatReconciliationDatabaseError,
    "invalid generated_at",
  );
});
