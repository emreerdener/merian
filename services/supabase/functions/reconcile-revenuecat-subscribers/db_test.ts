import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import {
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
    }], calls),
  );

  assertEquals(health, {
    generatedAt: "2026-07-26T03:30:00.000Z",
    dueCount: 12,
    expiredClaimCount: 1,
    oldestDueAt: "2026-07-26T02:45:00.000Z",
    oldestDueAgeSeconds: 2_700,
  });
  assertEquals(calls, [{
    name: "get_revenuecat_reconciliation_health",
    arguments: undefined,
  }]);
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
