import type { SupabaseClient, User } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import type {
  BoundSignoutPurchaseHandoff,
  CancelledSignoutPurchaseHandoff,
  CompletedSignoutPurchaseHandoff,
  PreparedSignoutPurchaseHandoff,
} from "./db.ts";
import { handleSignoutPurchaseHandoff } from "./handler.ts";

const NOW_MS = 1_786_500_000_000;
const SOURCE_ID = "550e8400-e29b-41d4-a716-446655440001";
const DESTINATION_ID = "550e8400-e29b-41d4-a716-446655440002";
const HANDOFF_ID = "550e8400-e29b-41d4-a716-446655440003";
const HANDOFF_SECRET = "A".repeat(43);
const EXPIRES_AT = "2026-09-10T00:00:00.000Z";

const supabaseAdmin = {} as SupabaseClient;

function user(id: string, isAnonymous: boolean): User {
  return { id, is_anonymous: isAnonymous } as User;
}

function request(
  operation: "prepare" | "bind" | "cancel" | "complete",
): Request {
  return new Request("https://example.test/transfer-signout-purchases", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(
      operation === "prepare" ? { operation } : {
        operation,
        handoff_id: HANDOFF_ID,
        handoff_secret: HANDOFF_SECRET,
      },
    ),
  });
}

function customerInfo(input: {
  product?: boolean;
  promo?: boolean;
  expiresAt?: string;
  requestDateMs?: number;
}) {
  const productIdentifier = input.product
    ? "merian_pro_annual"
    : "operator_beta";
  return {
    requestDateMs: input.requestDateMs ?? NOW_MS,
    subscriber: {
      entitlements: input.product || input.promo
        ? {
          pro: {
            product_identifier: productIdentifier,
            expires_date: input.expiresAt ?? "2027-08-01T00:00:00.000Z",
          },
        }
        : {},
      subscriptions: input.product || input.promo
        ? {
          [productIdentifier]: {
            expires_date: input.expiresAt,
            store: input.product ? "app_store" : "promotional",
          },
        }
        : {},
      non_subscriptions: {},
    },
  };
}

function passCustomerInfo() {
  return {
    requestDateMs: NOW_MS,
    subscriber: {
      entitlements: {},
      subscriptions: {},
      non_subscriptions: {
        pro_week: [{
          id: "pass-transaction",
          purchase_date: new Date(
            NOW_MS - 24 * 60 * 60 * 1_000,
          ).toISOString(),
          store: "app_store",
        }],
      },
    },
  };
}

function prepared(): PreparedSignoutPurchaseHandoff {
  return { handoffId: HANDOFF_ID, expiresAt: EXPIRES_AT };
}

function bound(
  expectedStoreAccess: BoundSignoutPurchaseHandoff["expectedStoreAccess"],
  status: BoundSignoutPurchaseHandoff["status"] = "bound",
  destinationVerifiedSnapshotAtMs: number | null = null,
  destinationVerifiedStoreAccess:
    BoundSignoutPurchaseHandoff["destinationVerifiedStoreAccess"] =
      status === "completed" ? expectedStoreAccess : null,
  sourceSnapshotAtMs = NOW_MS,
): BoundSignoutPurchaseHandoff {
  return {
    handoffId: HANDOFF_ID,
    sourceUserId: SOURCE_ID,
    destinationUserId: DESTINATION_ID,
    sourceSnapshotAtMs,
    expectedStoreAccess,
    status,
    destinationVerifiedSnapshotAtMs,
    destinationVerifiedStoreAccess,
    boundAt: "2026-08-12T00:00:00.000Z",
    alreadyBound: false,
  };
}

function completed(): CompletedSignoutPurchaseHandoff {
  return {
    handoffId: HANDOFF_ID,
    completedAt: "2026-08-12T00:00:01.000Z",
    alreadyCompleted: false,
  };
}

function cancelled(): CancelledSignoutPurchaseHandoff {
  return {
    handoffId: HANDOFF_ID,
    cancelledAt: "2026-08-12T00:00:00.000Z",
    alreadyCancelled: false,
  };
}

Deno.test("prepare snapshots StoreKit access and excludes an account promotion", async () => {
  const issued: Record<string, unknown>[] = [];
  const response = await handleSignoutPurchaseHandoff(
    request("prepare"),
    user(SOURCE_ID, false),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      fetchCustomerInfo: () => Promise.resolve(customerInfo({ promo: true })),
      issueHandoff: (
        _admin,
        _sourceUserId,
        secretHash,
        snapshotAtMs,
        expectedStoreAccess,
      ) => {
        issued.push({ secretHash, snapshotAtMs, expectedStoreAccess });
        return Promise.resolve(prepared());
      },
    },
  );

  assertEquals(response.status, 201);
  assertEquals(issued.length, 1);
  assertEquals(issued[0].snapshotAtMs, NOW_MS);
  assertEquals(issued[0].expectedStoreAccess, {
    targetTier: "free",
    expiresAt: null,
  });
  assertEquals(
    typeof issued[0].secretHash === "string" &&
      /^[0-9a-f]{64}$/.test(issued[0].secretHash as string),
    true,
  );
});

Deno.test("complete verifies destination StoreKit horizon before durable completion", async () => {
  const order: string[] = [];
  const expected = {
    targetTier: "pro" as const,
    expiresAt: "2027-08-01T00:00:00.000Z",
  };
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () => {
        order.push("bind");
        return Promise.resolve(bound(expected));
      },
      fetchCustomerInfo: () => {
        order.push("fetch-destination");
        return Promise.resolve(
          customerInfo({ product: true, expiresAt: expected.expiresAt }),
        );
      },
      completeHandoff: (
        _admin,
        _handoffId,
        _secretHash,
        destinationUserId,
        destinationSnapshotAtMs,
        destinationStoreAccess,
      ) => {
        assertEquals(destinationUserId, DESTINATION_ID);
        assertEquals(destinationSnapshotAtMs, NOW_MS);
        assertEquals(destinationStoreAccess, expected);
        order.push("complete-database");
        return Promise.resolve(completed());
      },
      claimReconciliation: () => {
        order.push("claim-destination");
        return Promise.resolve({
          userId: DESTINATION_ID,
          lookupAppUserId: DESTINATION_ID.toUpperCase(),
          claimToken: "550e8400-e29b-41d4-a716-446655440004",
          claimExpiresAt: "2026-08-12T00:02:00.000Z",
          allowNonSubscriptionPassGrant: true,
        });
      },
      applyReconciliation: () => {
        order.push("apply-destination");
        return Promise.resolve(true);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(order, [
    "bind",
    "fetch-destination",
    "complete-database",
    "claim-destination",
    "apply-destination",
  ]);
});

Deno.test("completed replay uses its attested snapshot after finite access expires", async () => {
  const order: string[] = [];
  const verifiedSnapshotAtMs = NOW_MS - 1_000;
  const expected = {
    targetTier: "pro" as const,
    expiresAt: new Date(NOW_MS - 500).toISOString(),
  };
  let appliedSnapshotAtMs: number | undefined;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () => {
        order.push("bind-completed");
        return Promise.resolve(
          bound(
            expected,
            "completed",
            verifiedSnapshotAtMs,
            expected,
            NOW_MS - 2_000,
          ),
        );
      },
      fetchCustomerInfo: () => {
        order.push("unexpected-provider-fetch");
        return Promise.resolve(customerInfo({}));
      },
      completeHandoff: (
        _admin,
        _handoffId,
        _secretHash,
        _destinationUserId,
        destinationSnapshotAtMs,
        destinationStoreAccess,
      ) => {
        order.push("requeue-completed");
        assertEquals(destinationSnapshotAtMs, verifiedSnapshotAtMs);
        assertEquals(destinationStoreAccess, expected);
        return Promise.resolve({ ...completed(), alreadyCompleted: true });
      },
      claimReconciliation: () => {
        order.push("claim-destination");
        return Promise.resolve({
          userId: DESTINATION_ID,
          lookupAppUserId: DESTINATION_ID.toUpperCase(),
          claimToken: "550e8400-e29b-41d4-a716-446655440004",
          claimExpiresAt: "2026-08-12T00:02:00.000Z",
          allowNonSubscriptionPassGrant: false,
        });
      },
      applyReconciliation: (_claim, snapshotAtMs) => {
        order.push("apply-original-attestation");
        appliedSnapshotAtMs = snapshotAtMs;
        return Promise.resolve(false);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(appliedSnapshotAtMs, verifiedSnapshotAtMs);
  assertEquals(order, [
    "bind-completed",
    "requeue-completed",
    "claim-destination",
    "apply-original-attestation",
  ]);
});

Deno.test("finite access can finish free after expiring during a pending handoff", async () => {
  const expected = {
    targetTier: "pro" as const,
    expiresAt: new Date(NOW_MS - 1_000).toISOString(),
  };
  const fetchedAppUserIds: string[] = [];
  let completedStoreAccess: unknown;
  let appliedStoreAccess: unknown;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () =>
        Promise.resolve(
          bound(expected, "bound", null, null, NOW_MS - 2_000),
        ),
      fetchCustomerInfo: (appUserId) => {
        fetchedAppUserIds.push(appUserId);
        return Promise.resolve(customerInfo({}));
      },
      completeHandoff: (
        _admin,
        _handoffId,
        _secretHash,
        _destinationUserId,
        _snapshotAtMs,
        destinationStoreAccess,
      ) => {
        completedStoreAccess = destinationStoreAccess;
        return Promise.resolve(completed());
      },
      claimReconciliation: () =>
        Promise.resolve({
          userId: DESTINATION_ID,
          lookupAppUserId: DESTINATION_ID.toUpperCase(),
          claimToken: "550e8400-e29b-41d4-a716-446655440004",
          claimExpiresAt: "2026-08-12T00:02:00.000Z",
          allowNonSubscriptionPassGrant: false,
        }),
      applyReconciliation: (_claim, _snapshot, tier, expiresAt) => {
        appliedStoreAccess = { targetTier: tier, expiresAt };
        return Promise.resolve(true);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(fetchedAppUserIds, [
    DESTINATION_ID.toUpperCase(),
    SOURCE_ID.toUpperCase(),
  ]);
  assertEquals(completedStoreAccess, {
    targetTier: "free",
    expiresAt: null,
  });
  assertEquals(appliedStoreAccess, {
    targetTier: "free",
    expiresAt: null,
  });
});

Deno.test("post-expiry completion ignores detached pass history on both customers", async () => {
  const expected = {
    targetTier: "pro" as const,
    expiresAt: new Date(NOW_MS - 1_000).toISOString(),
  };
  let completedStoreAccess: unknown;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () =>
        Promise.resolve(
          bound(expected, "bound", null, null, NOW_MS - 2_000),
        ),
      fetchCustomerInfo: () => Promise.resolve(passCustomerInfo()),
      completeHandoff: (
        _admin,
        _handoffId,
        _secretHash,
        _destinationUserId,
        _snapshotAtMs,
        destinationStoreAccess,
      ) => {
        completedStoreAccess = destinationStoreAccess;
        return Promise.resolve(completed());
      },
      claimReconciliation: () =>
        Promise.resolve({
          userId: DESTINATION_ID,
          lookupAppUserId: DESTINATION_ID.toUpperCase(),
          claimToken: "550e8400-e29b-41d4-a716-446655440004",
          claimExpiresAt: "2026-08-12T00:02:00.000Z",
          allowNonSubscriptionPassGrant: false,
        }),
      applyReconciliation: () => Promise.resolve(true),
    },
  );

  assertEquals(response.status, 200);
  assertEquals(completedStoreAccess, {
    targetTier: "free",
    expiresAt: null,
  });
});

Deno.test("post-expiry completion preserves a renewal present on both customers", async () => {
  const expected = {
    targetTier: "pro" as const,
    expiresAt: new Date(NOW_MS - 1_000).toISOString(),
  };
  const sourceRenewal = new Date(NOW_MS + 30 * 24 * 60 * 60 * 1_000)
    .toISOString();
  const destinationRenewal = new Date(NOW_MS + 60 * 24 * 60 * 60 * 1_000)
    .toISOString();
  let completedStoreAccess: unknown;
  let appliedStoreAccess: unknown;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () =>
        Promise.resolve(
          bound(expected, "bound", null, null, NOW_MS - 2_000),
        ),
      fetchCustomerInfo: (appUserId) =>
        Promise.resolve(
          customerInfo({
            product: true,
            expiresAt: appUserId === SOURCE_ID.toUpperCase()
              ? sourceRenewal
              : destinationRenewal,
          }),
        ),
      completeHandoff: (
        _admin,
        _handoffId,
        _secretHash,
        _destinationUserId,
        _snapshotAtMs,
        destinationStoreAccess,
      ) => {
        completedStoreAccess = destinationStoreAccess;
        return Promise.resolve(completed());
      },
      claimReconciliation: () =>
        Promise.resolve({
          userId: DESTINATION_ID,
          lookupAppUserId: DESTINATION_ID.toUpperCase(),
          claimToken: "550e8400-e29b-41d4-a716-446655440004",
          claimExpiresAt: "2026-08-12T00:02:00.000Z",
          allowNonSubscriptionPassGrant: false,
        }),
      applyReconciliation: (_claim, _snapshot, tier, expiresAt) => {
        appliedStoreAccess = { targetTier: tier, expiresAt };
        return Promise.resolve(true);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(completedStoreAccess, {
    targetTier: "pro",
    expiresAt: destinationRenewal,
  });
  assertEquals(appliedStoreAccess, completedStoreAccess);
});

Deno.test("expired prepared access remains pending when the source renewed first", async () => {
  const expected = {
    targetTier: "pro" as const,
    expiresAt: new Date(NOW_MS - 1_000).toISOString(),
  };
  const renewedExpiresAt = new Date(NOW_MS + 30 * 24 * 60 * 60 * 1_000)
    .toISOString();
  let completeCount = 0;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () =>
        Promise.resolve(
          bound(expected, "bound", null, null, NOW_MS - 2_000),
        ),
      fetchCustomerInfo: (appUserId) =>
        Promise.resolve(
          appUserId === SOURCE_ID.toUpperCase()
            ? customerInfo({ product: true, expiresAt: renewedExpiresAt })
            : customerInfo({}),
        ),
      completeHandoff: () => {
        completeCount += 1;
        return Promise.resolve(completed());
      },
    },
  );
  const payload = await response.json();

  assertEquals(response.status, 503);
  assertEquals(payload.code, "purchase_transfer_pending");
  assertEquals(completeCount, 0);
});

Deno.test("prepare refuses detached pass history without matching server access", async () => {
  let issueCount = 0;
  const response = await handleSignoutPurchaseHandoff(
    request("prepare"),
    user(SOURCE_ID, false),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      fetchCustomerInfo: () => Promise.resolve(passCustomerInfo()),
      readSourceEntitlement: () =>
        Promise.resolve({ targetTier: "free", expiresAt: null }),
      issueHandoff: () => {
        issueCount += 1;
        return Promise.resolve(prepared());
      },
    },
  );
  const payload = await response.json();

  assertEquals(response.status, 503);
  assertEquals(payload.code, "purchase_projection_pending");
  assertEquals(issueCount, 0);
});

Deno.test("prepare accepts an active pass only when its database expiry matches", async () => {
  const passExpiresAt = new Date(
    NOW_MS + 6 * 24 * 60 * 60 * 1_000,
  ).toISOString();
  let expectedAccess: unknown;
  const response = await handleSignoutPurchaseHandoff(
    request("prepare"),
    user(SOURCE_ID, false),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      fetchCustomerInfo: () => Promise.resolve(passCustomerInfo()),
      readSourceEntitlement: () =>
        Promise.resolve({ targetTier: "pro", expiresAt: passExpiresAt }),
      issueHandoff: (_admin, _source, _hash, _snapshot, expected) => {
        expectedAccess = expected;
        return Promise.resolve(prepared());
      },
    },
  );

  assertEquals(response.status, 201);
  assertEquals(expectedAccess, {
    targetTier: "pro",
    expiresAt: passExpiresAt,
  });
});

Deno.test("complete stays retryable and performs no database completion before receipt transfer", async () => {
  let completedCount = 0;
  let claimedCount = 0;
  const response = await handleSignoutPurchaseHandoff(
    request("complete"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      bindHandoff: () =>
        Promise.resolve(bound({
          targetTier: "pro",
          expiresAt: "2027-08-01T00:00:00.000Z",
        })),
      fetchCustomerInfo: () => Promise.resolve(customerInfo({})),
      completeHandoff: () => {
        completedCount += 1;
        return Promise.resolve(completed());
      },
      claimReconciliation: () => {
        claimedCount += 1;
        return Promise.reject(new Error("must not claim"));
      },
    },
  );
  const payload = await response.json();

  assertEquals(response.status, 503);
  assertEquals(payload.code, "purchase_transfer_pending");
  assertEquals(completedCount, 0);
  assertEquals(claimedCount, 0);
});

Deno.test("prepare rejects an anonymous source before provider or database work", async () => {
  let externalCalls = 0;
  const response = await handleSignoutPurchaseHandoff(
    request("prepare"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      fetchCustomerInfo: () => {
        externalCalls += 1;
        return Promise.resolve(customerInfo({}));
      },
      issueHandoff: () => {
        externalCalls += 1;
        return Promise.resolve(prepared());
      },
    },
  );

  assertEquals(response.status, 403);
  assertEquals(externalCalls, 0);
});

Deno.test("cancel needs the linked source but no RevenueCat configuration", async () => {
  let cancelCount = 0;
  const response = await handleSignoutPurchaseHandoff(
    request("cancel"),
    user(SOURCE_ID, false),
    supabaseAdmin,
    {
      apiKey: "",
      cancelHandoff: () => {
        cancelCount += 1;
        return Promise.resolve(cancelled());
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(cancelCount, 1);

  const anonymousResponse = await handleSignoutPurchaseHandoff(
    request("cancel"),
    user(DESTINATION_ID, true),
    supabaseAdmin,
    {
      apiKey: "",
      cancelHandoff: () => {
        cancelCount += 1;
        return Promise.resolve(cancelled());
      },
    },
  );
  assertEquals(anonymousResponse.status, 403);
  assertEquals(cancelCount, 1);
});
