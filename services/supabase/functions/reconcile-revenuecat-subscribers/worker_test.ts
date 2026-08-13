import { assertEquals, assertRejects } from "@std/assert";
import {
  PurchasePrincipalHealth,
  PurchasePrincipalReconciliationClaim,
  RevenueCatReconciliationClaim,
  RevenueCatReconciliationHealth,
} from "./db.ts";
import {
  processRevenueCatReconciliations,
  revenueCatReconciliationHealthStatus,
} from "./worker.ts";

const CLAIM: RevenueCatReconciliationClaim = {
  userId: "550e8400-e29b-41d4-a716-446655440000",
  lookupAppUserId: "revenuecat-customer",
  claimToken: "650e8400-e29b-41d4-a716-446655440000",
  claimExpiresAt: "2026-07-25T06:00:00.000Z",
  allowNonSubscriptionPassGrant: true,
};

const PRINCIPAL_CLAIM: PurchasePrincipalReconciliationClaim = {
  purchasePrincipalId: "750e8400-e29b-41d4-a716-446655440000",
  lookupAppUserId: "MERIAN_PP_00112233445566778899AABBCCDDEEFF",
  claimToken: "850e8400-e29b-41d4-a716-446655440000",
  claimExpiresAt: "2026-07-25T06:00:00.000Z",
  allowNonSubscriptionPassGrant: true,
};

const HEALTHY_QUEUE: RevenueCatReconciliationHealth = {
  generatedAt: "2026-07-25T05:00:00.000Z",
  dueCount: 0,
  expiredClaimCount: 0,
  oldestDueAt: null,
  oldestDueAgeSeconds: null,
  signoutPreparedCount: 0,
  signoutBoundCount: 0,
  oldestSignoutPendingAt: null,
  oldestSignoutPendingAgeSeconds: null,
};

const HEALTHY_PURCHASE_PRINCIPALS: PurchasePrincipalHealth = {
  generatedAt: "2026-07-25T05:00:00.000Z",
  activePrincipalCount: 0,
  pendingPrincipalCount: 0,
  unboundActivePrincipalCount: 0,
  dueReconciliationCount: 0,
  expiredClaimCount: 0,
  oldestDueAt: null,
  oldestDueAgeSeconds: null,
  oldestPendingAt: null,
  oldestPendingAgeSeconds: null,
};

function pagedClaims(
  pages: RevenueCatReconciliationClaim[][],
): () => Promise<RevenueCatReconciliationClaim[]> {
  let pageIndex = 0;
  return () => Promise.resolve(pages[pageIndex++] ?? []);
}

Deno.test("reconciliation applies authoritative recurring expiry", async () => {
  const writes: Array<Record<string, unknown>> = [];
  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: pagedClaims([[CLAIM], []]),
      claimPrincipal: () => Promise.resolve([]),
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
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
      monotonicNow: () => 0,
    },
  );

  assertEquals(result, {
    claimed: 1,
    reconciled: 1,
    applied: 1,
    stale: 0,
    failed: 0,
    claimBatches: 2,
    queueDrained: true,
    runtimeDeadlineReached: false,
    healthStatus: "ok",
    health: HEALTHY_QUEUE,
    purchasePrincipalHealth: HEALTHY_PURCHASE_PRINCIPALS,
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
      claim: pagedClaims([
        [
          CLAIM,
          {
            ...CLAIM,
            userId: "550e8400-e29b-41d4-a716-446655440001",
            lookupAppUserId: "revenuecat-customer-2",
          },
        ],
        [],
      ]),
      claimPrincipal: () => Promise.resolve([]),
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
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => 1,
      monotonicNow: () => 0,
    },
  );

  assertEquals(result, {
    claimed: 2,
    reconciled: 1,
    applied: 0,
    stale: 1,
    failed: 1,
    claimBatches: 2,
    queueDrained: true,
    runtimeDeadlineReached: false,
    healthStatus: "ok",
    health: HEALTHY_QUEUE,
    purchasePrincipalHealth: HEALTHY_PURCHASE_PRINCIPALS,
  });
  assertEquals(failed, [CLAIM.userId]);
});

Deno.test("reconciliation failure logs omit customer and provider identity", async () => {
  const logs: string[] = [];
  const persistedCodes: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(String(args[0]));

  try {
    const providerError = new Error(
      `provider body leaked ${CLAIM.lookupAppUserId} ${CLAIM.userId}`,
    );
    providerError.name = CLAIM.userId;
    await processRevenueCatReconciliations(
      {} as never,
      "sk_test_secret",
      {
        claim: pagedClaims([[CLAIM], []]),
        claimPrincipal: () => Promise.resolve([]),
        fetchCustomerInfo: () => Promise.reject(providerError),
        apply: () => Promise.resolve(false),
        fail: (_claim, errorCode) => {
          persistedCodes.push(errorCode);
          const persistenceError = new Error(
            `database detail leaked ${CLAIM.claimToken}`,
          );
          persistenceError.name = CLAIM.claimToken;
          return Promise.reject(persistenceError);
        },
        health: () => Promise.resolve(HEALTHY_QUEUE),
        principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
        fetchImpl: fetch,
        now: () => 1,
        monotonicNow: () => 0,
      },
    );
  } finally {
    console.error = original;
  }

  assertEquals(logs.length, 2);
  assertEquals(persistedCodes, ["reconciliation_failed"]);
  const serialized = logs.join("\n");
  for (
    const forbidden of [
      CLAIM.userId,
      CLAIM.lookupAppUserId,
      CLAIM.claimToken,
      "provider body leaked",
      "database detail leaked",
    ]
  ) {
    assertEquals(serialized.includes(forbidden), false);
  }
  for (const log of logs) {
    const parsed = JSON.parse(log);
    assertEquals(parsed.identity_kind, "legacy");
    assertEquals(typeof parsed.event, "string");
    assertEquals(typeof parsed.code, "string");
    assertEquals(typeof parsed.ts, "string");
  }
});

Deno.test("reconciliation cannot restore a historical pass after revocation", async () => {
  const writes: Array<Record<string, unknown>> = [];
  await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: pagedClaims([
        [{
          ...CLAIM,
          allowNonSubscriptionPassGrant: false,
        }],
        [],
      ]),
      claimPrincipal: () => Promise.resolve([]),
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
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
      monotonicNow: () => 0,
    },
  );

  assertEquals(writes, [{ tier: "free", expiresAt: null }]);
});

Deno.test("stable principal reconciliation keeps StoreKit and promotion state separate", async () => {
  let principalClaimPage = 0;
  const writes: Array<Record<string, unknown>> = [];
  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () => Promise.resolve([]),
      claimPrincipal: () =>
        Promise.resolve(principalClaimPage++ === 0 ? [PRINCIPAL_CLAIM] : []),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: Date.parse("2026-07-25T05:00:00.000Z"),
          subscriber: {
            entitlements: {
              pro: {
                product_identifier: "merian_pro_annual",
                expires_date: "2026-08-25T05:00:00.000Z",
              },
              "Naturalist Tier": {
                product_identifier: "operator_beta",
                expires_date: "2026-07-30T05:00:00.000Z",
              },
            },
            subscriptions: {
              merian_pro_annual: { store: "app_store" },
              operator_beta: { store: "promotional" },
            },
            non_subscriptions: {},
          },
        }),
      apply: () => Promise.reject(new Error("legacy lane must stay empty")),
      applyPrincipal: (
        claim,
        snapshot,
        storeTier,
        storeExpiresAt,
        accountGrantTier,
        accountGrantExpiresAt,
      ) => {
        writes.push({
          claim,
          snapshot,
          storeTier,
          storeExpiresAt,
          accountGrantTier,
          accountGrantExpiresAt,
        });
        return Promise.resolve(true);
      },
      fail: () => Promise.resolve(),
      failPrincipal: () => Promise.resolve(),
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
      monotonicNow: () => 0,
    },
  );

  assertEquals(result.claimed, 1);
  assertEquals(result.applied, 1);
  assertEquals(writes, [{
    claim: PRINCIPAL_CLAIM,
    snapshot: Date.parse("2026-07-25T05:00:00.000Z"),
    storeTier: "pro",
    storeExpiresAt: "2026-08-25T05:00:00.000Z",
    accountGrantTier: "pro",
    accountGrantExpiresAt: "2026-07-30T05:00:00.000Z",
  }]);
});

Deno.test("scheduled repair rejects stale provider snapshots in both identity lanes", async () => {
  const failed: string[] = [];
  let principalClaimPage = 0;
  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: pagedClaims([[CLAIM], []]),
      claimPrincipal: () =>
        Promise.resolve(
          principalClaimPage++ === 0 ? [PRINCIPAL_CLAIM] : [],
        ),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: Date.parse("2026-07-25T04:00:00.000Z"),
          subscriber: {
            entitlements: {
              pro: { expires_date: null },
            },
          },
        }),
      apply: () => Promise.reject(new Error("stale legacy snapshot applied")),
      applyPrincipal: () =>
        Promise.reject(new Error("stale principal snapshot applied")),
      fail: () => {
        failed.push("legacy");
        return Promise.resolve();
      },
      failPrincipal: () => {
        failed.push("purchase_principal");
        return Promise.resolve();
      },
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
      monotonicNow: () => 0,
    },
  );

  assertEquals(result.failed, 2);
  assertEquals(result.applied, 0);
  assertEquals(failed.sort(), ["legacy", "purchase_principal"]);
});

Deno.test("stable principal reconciliation cannot restore revoked pass history", async () => {
  let principalClaimPage = 0;
  const writes: Array<Record<string, unknown>> = [];
  await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () => Promise.resolve([]),
      claimPrincipal: () =>
        Promise.resolve(
          principalClaimPage++ === 0
            ? [{
              ...PRINCIPAL_CLAIM,
              allowNonSubscriptionPassGrant: false,
            }]
            : [],
        ),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: Date.parse("2026-07-25T05:00:00.000Z"),
          subscriber: {
            entitlements: {},
            subscriptions: {},
            non_subscriptions: {
              pro_week: [{
                id: "historical-refunded-pass",
                purchase_date: "2026-07-23T05:00:00.000Z",
                store: "app_store",
              }],
            },
          },
        }),
      apply: () => Promise.reject(new Error("legacy lane must stay empty")),
      applyPrincipal: (
        _claim,
        _snapshot,
        storeTier,
        storeExpiresAt,
        accountGrantTier,
        accountGrantExpiresAt,
      ) => {
        writes.push({
          storeTier,
          storeExpiresAt,
          accountGrantTier,
          accountGrantExpiresAt,
        });
        return Promise.resolve(true);
      },
      fail: () => Promise.resolve(),
      failPrincipal: () => Promise.resolve(),
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      now: () => Date.parse("2026-07-25T05:00:00.000Z"),
      monotonicNow: () => 0,
    },
  );

  assertEquals(writes, [{
    storeTier: "free",
    storeExpiresAt: null,
    accountGrantTier: "free",
    accountGrantExpiresAt: null,
  }]);
});

Deno.test("claim failures fail the invocation for cron retry visibility", async () => {
  await assertRejects(
    () =>
      processRevenueCatReconciliations({} as never, "sk_test_secret", {
        claim: () => Promise.reject(new Error("database unavailable")),
        claimPrincipal: () => Promise.resolve([]),
      }),
    Error,
    "database unavailable",
  );
});

Deno.test("reconciliation drains beyond the former ten-claim ceiling", async () => {
  const claims = Array.from({ length: 12 }, (_, index) => ({
    ...CLAIM,
    userId: `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
    lookupAppUserId: `revenuecat-customer-${index + 1}`,
    claimToken: `00000000-0000-4001-8000-${
      String(index + 1).padStart(12, "0")
    }`,
  }));
  const requestedLimits: number[] = [];
  const claim = pagedClaims([
    claims.slice(0, 3),
    claims.slice(3, 6),
    claims.slice(6, 9),
    claims.slice(9),
    [],
  ]);

  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: (_client, limit) => {
        requestedLimits.push(limit ?? -1);
        return claim();
      },
      claimPrincipal: () => Promise.resolve([]),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: 1,
          subscriber: { entitlements: {} },
        }),
      apply: () => Promise.resolve(true),
      fail: () => Promise.resolve(),
      health: () => Promise.resolve(HEALTHY_QUEUE),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => 1,
      monotonicNow: () => 0,
    },
  );

  assertEquals(result.claimed, 12);
  assertEquals(result.applied, 12);
  assertEquals(result.claimBatches, 5);
  assertEquals(result.queueDrained, true);
  assertEquals(result.runtimeDeadlineReached, false);
  assertEquals(requestedLimits, [3, 3, 3, 3, 3]);
});

Deno.test("reconciliation stops claiming at the runtime cutoff", async () => {
  let elapsedMs = 0;
  let claimCalls = 0;
  const backlogHealth: RevenueCatReconciliationHealth = {
    ...HEALTHY_QUEUE,
    dueCount: 5,
    oldestDueAt: "2026-07-25T04:40:00.000Z",
    oldestDueAgeSeconds: 20 * 60,
  };

  const result = await processRevenueCatReconciliations(
    {} as never,
    "sk_test_secret",
    {
      claim: () => {
        claimCalls += 1;
        return Promise.resolve([CLAIM]);
      },
      claimPrincipal: () => Promise.resolve([]),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: 1,
          subscriber: { entitlements: {} },
        }),
      apply: () => {
        elapsedMs = 60_001;
        return Promise.resolve(true);
      },
      fail: () => Promise.resolve(),
      health: () => Promise.resolve(backlogHealth),
      principalHealth: () => Promise.resolve(HEALTHY_PURCHASE_PRINCIPALS),
      fetchImpl: fetch,
      now: () => 1,
      monotonicNow: () => elapsedMs,
    },
  );

  assertEquals(claimCalls, 1);
  assertEquals(result.claimed, 1);
  assertEquals(result.queueDrained, false);
  assertEquals(result.runtimeDeadlineReached, true);
  assertEquals(result.healthStatus, "ok");
});

Deno.test("oldest due age and expired leases drive health severity", () => {
  assertEquals(
    revenueCatReconciliationHealthStatus({
      ...HEALTHY_QUEUE,
      expiredClaimCount: 1,
    }),
    "warning",
  );
  assertEquals(
    revenueCatReconciliationHealthStatus({
      ...HEALTHY_QUEUE,
      dueCount: 1,
      oldestDueAt: "2026-07-25T04:30:00.000Z",
      oldestDueAgeSeconds: 30 * 60,
    }),
    "warning",
  );
  assertEquals(
    revenueCatReconciliationHealthStatus({
      ...HEALTHY_QUEUE,
      dueCount: 1,
      oldestDueAt: "2026-07-25T04:00:00.000Z",
      oldestDueAgeSeconds: 60 * 60,
    }),
    "critical",
  );
  assertEquals(
    revenueCatReconciliationHealthStatus({
      ...HEALTHY_QUEUE,
      signoutBoundCount: 1,
      oldestSignoutPendingAt: "2026-07-25T04:30:00.000Z",
      oldestSignoutPendingAgeSeconds: 30 * 60,
    }),
    "warning",
  );
  assertEquals(
    revenueCatReconciliationHealthStatus(
      HEALTHY_QUEUE,
      {
        ...HEALTHY_PURCHASE_PRINCIPALS,
        unboundActivePrincipalCount: 1,
      },
    ),
    "warning",
  );
  assertEquals(
    revenueCatReconciliationHealthStatus(
      HEALTHY_QUEUE,
      {
        ...HEALTHY_PURCHASE_PRINCIPALS,
        dueReconciliationCount: 1,
        oldestDueAt: "2026-07-25T04:00:00.000Z",
        oldestDueAgeSeconds: 60 * 60,
      },
    ),
    "critical",
  );
});
