import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { RevenueCatReconciliationClaim } from "./db.ts";
import { processRevenueCatReconciliations } from "./worker.ts";

const CLAIM: RevenueCatReconciliationClaim = {
  userId: "550e8400-e29b-41d4-a716-446655440000",
  lookupAppUserId: "revenuecat-customer",
  claimToken: "650e8400-e29b-41d4-a716-446655440000",
  claimExpiresAt: "2026-07-25T06:00:00.000Z",
  allowNonSubscriptionPassGrant: true,
};

Deno.test("reconciliation applies authoritative recurring expiry", async () => {
  const writes: Array<Record<string, unknown>> = [];
  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () => Promise.resolve([CLAIM]),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: Date.parse("2026-07-25T05:00:00.000Z"),
          subscriber: {
            entitlements: {
              pro: { expires_date: "2026-08-25T05:00:00.000Z" },
            },
          },
        }),
      apply: (
        claim,
        snapshot,
        tier,
        expiresAt,
      ) => {
        writes.push({ claim, snapshot, tier, expiresAt });
        return Promise.resolve(true);
      },
      fail: () => Promise.resolve(),
      fetchImpl: fetch,
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
    },
  );

  assertEquals(result, {
    claimed: 1,
    reconciled: 1,
    applied: 1,
    stale: 0,
    failed: 0,
  });
  assertEquals(writes[0], {
    claim: CLAIM,
    snapshot: Date.parse("2026-07-25T05:00:00.000Z"),
    tier: "pro",
    expiresAt: "2026-08-25T05:00:00.000Z",
  });
});

Deno.test("reconciliation persists failures without aborting sibling claims", async () => {
  const failed: string[] = [];
  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () =>
        Promise.resolve([
          CLAIM,
          {
            ...CLAIM,
            userId: "550e8400-e29b-41d4-a716-446655440001",
            lookupAppUserId: "revenuecat-customer-2",
          },
        ]),
      fetchCustomerInfo: (lookupAppUserId) => {
        if (lookupAppUserId === CLAIM.lookupAppUserId) {
          return Promise.reject(new Error("provider unavailable"));
        }
        return Promise.resolve({
          requestDateMs: 1,
          subscriber: { entitlements: {} },
        });
      },
      apply: () => Promise.resolve(false),
      fail: (claim) => {
        failed.push(claim.userId);
        return Promise.resolve();
      },
      fetchImpl: fetch,
      now: () => 1,
    },
  );

  assertEquals(result, {
    claimed: 2,
    reconciled: 1,
    applied: 0,
    stale: 1,
    failed: 1,
  });
  assertEquals(failed, [CLAIM.userId]);
});

Deno.test("reconciliation cannot restore a historical pass after revocation", async () => {
  const writes: Array<Record<string, unknown>> = [];
  await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () =>
        Promise.resolve([{
          ...CLAIM,
          allowNonSubscriptionPassGrant: false,
        }]),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: Date.parse("2026-07-25T05:00:00.000Z"),
          subscriber: {
            entitlements: {},
            non_subscriptions: {
              pro_week: [{
                id: "historical-refunded-pass",
                purchase_date: "2026-07-23T05:00:00.000Z",
              }],
            },
          },
        }),
      apply: (_claim, _snapshot, tier, expiresAt) => {
        writes.push({ tier, expiresAt });
        return Promise.resolve(true);
      },
      fail: () => Promise.resolve(),
      fetchImpl: fetch,
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
    },
  );

  assertEquals(writes, [{ tier: "free", expiresAt: null }]);
});

Deno.test("claim failures fail the invocation for cron retry visibility", async () => {
  await assertRejects(
    () =>
      processRevenueCatReconciliations({} as never, "sk_test_secret", {
        claim: () => Promise.reject(new Error("database unavailable")),
      }),
    Error,
    "database unavailable",
  );
});
