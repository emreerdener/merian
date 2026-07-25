import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { SEVEN_DAY_PASS_PRODUCT_ID } from "../_shared/subscriptionPass.ts";
import { RevenueCatWebhookEvent } from "./protocol.ts";
import {
  deriveRevenueCatEntitlementState,
  fetchRevenueCatCustomerInfo,
  RevenueCatApiError,
  RevenueCatCustomerInfo,
} from "./subscriber.ts";

const SNAPSHOT_MS = Date.parse("2026-07-23T12:00:00.000Z");

function event(
  overrides: Partial<RevenueCatWebhookEvent> = {},
): RevenueCatWebhookEvent {
  return {
    id: "event-123",
    type: "RENEWAL",
    eventTimestampMs: SNAPSHOT_MS - 1_000,
    appUserId: "550e8400-e29b-41d4-a716-446655440000",
    originalAppUserId: null,
    aliases: [],
    transferredFrom: [],
    transferredTo: [],
    productId: "merian_pro_annual",
    transactionId: null,
    originalTransactionId: null,
    ...overrides,
  };
}

function customerInfo(
  subscriber: Record<string, unknown>,
): RevenueCatCustomerInfo {
  return { requestDateMs: SNAPSHOT_MS, subscriber };
}

Deno.test("authoritative active entitlement grants Pro independent of event type", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {
        pro: {
          expires_date: "2026-08-23T12:00:00.000Z",
        },
      },
    }),
    event({ type: "EXPIRATION" }),
  );

  assertEquals(state, {
    targetTier: "pro",
    expiresAt: "2026-08-23T12:00:00.000Z",
  });
});

Deno.test("recurring entitlement persists the later billing-grace deadline", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {
        pro: {
          expires_date: "2026-07-24T12:00:00.000Z",
          grace_period_expires_date: "2026-07-27T12:00:00.000Z",
        },
      },
    }),
    event(),
  );

  assertEquals(state, {
    targetTier: "pro",
    expiresAt: "2026-07-27T12:00:00.000Z",
  });
});

Deno.test("null recurring expiration is reserved for lifetime access", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {
        "Naturalist Tier": {
          expires_date: null,
        },
      },
    }),
    event(),
  );

  assertEquals(state, { targetTier: "pro", expiresAt: null });
});

Deno.test("expired entitlement and absent pass fail closed to free", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {
        "Naturalist Tier": {
          expires_date: "2026-07-22T12:00:00.000Z",
        },
      },
      non_subscriptions: {},
    }),
    event(),
  );

  assertEquals(state, { targetTier: "free", expiresAt: null });
});

Deno.test("authoritative pro_week transaction grants only its remaining seven-day window", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "pass-transaction",
          purchase_date: "2026-07-20T12:00:00.000Z",
        }],
      },
    }),
    event({
      type: "NON_RENEWING_PURCHASE",
      productId: SEVEN_DAY_PASS_PRODUCT_ID,
      transactionId: "pass-transaction",
    }),
  );

  assertEquals(state, {
    targetTier: "pro",
    expiresAt: "2026-07-27T12:00:00.000Z",
  });
});

Deno.test("pass refund excludes the refunded transaction but preserves a newer purchase", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [
          {
            id: "refunded-pass",
            purchase_date: "2026-07-19T12:00:00.000Z",
          },
          {
            id: "newer-pass",
            purchase_date: "2026-07-22T12:00:00.000Z",
          },
        ],
      },
    }),
    event({
      type: "REFUND",
      productId: SEVEN_DAY_PASS_PRODUCT_ID,
      transactionId: "refunded-pass",
    }),
  );

  assertEquals(state, {
    targetTier: "pro",
    expiresAt: "2026-07-29T12:00:00.000Z",
  });
});

Deno.test("unmatched pass revocation fails closed for earlier transactions", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "provider-used-a-different-id",
          purchase_date: "2026-07-20T12:00:00.000Z",
        }],
      },
    }),
    event({
      type: "REFUND",
      eventTimestampMs: Date.parse("2026-07-22T12:00:00.000Z"),
      productId: SEVEN_DAY_PASS_PRODUCT_ID,
      transactionId: "unmatched-refund-id",
    }),
  );

  assertEquals(state, { targetTier: "free", expiresAt: null });
});

Deno.test("future-dated pass transaction fails closed", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "future-pass",
          purchase_date: "2026-07-24T12:00:00.000Z",
        }],
      },
    }),
    event({
      type: "NON_RENEWING_PURCHASE",
      productId: SEVEN_DAY_PASS_PRODUCT_ID,
      transactionId: "future-pass",
    }),
  );

  assertEquals(state, { targetTier: "free", expiresAt: null });
});

Deno.test("periodic repair cannot restore a pass after a free watermark", () => {
  const state = deriveRevenueCatEntitlementState(
    customerInfo({
      entitlements: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "historical-refunded-pass",
          purchase_date: "2026-07-20T12:00:00.000Z",
        }],
      },
    }),
    undefined,
    false,
  );

  assertEquals(state, { targetTier: "free", expiresAt: null });
});

Deno.test("CustomerInfo fetch uses the server API key and validates the snapshot", async () => {
  let requestedUrl = "";
  let requestedAuthorization = "";
  const fakeFetch = ((
    input: string | URL | Request,
    init?: RequestInit,
  ) => {
    requestedUrl = String(input);
    requestedAuthorization = new Headers(init?.headers).get("Authorization") ??
      "";
    return Promise.resolve(
      new Response(
        JSON.stringify({
          request_date_ms: SNAPSHOT_MS,
          subscriber: { entitlements: {} },
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;

  const result = await fetchRevenueCatCustomerInfo(
    "user/with spaces",
    "sk_test_secret",
    fakeFetch,
  );

  assertEquals(
    requestedUrl,
    "https://api.revenuecat.com/v1/subscribers/user%2Fwith%20spaces",
  );
  assertEquals(requestedAuthorization, "Bearer sk_test_secret");
  assertEquals(result.requestDateMs, SNAPSHOT_MS);
});

Deno.test("CustomerInfo failure is retryable and never becomes free state", async () => {
  const failingFetch = (() =>
    Promise.resolve(
      new Response("unavailable", { status: 503 }),
    )) as typeof fetch;

  await assertRejects(
    () =>
      fetchRevenueCatCustomerInfo(
        "550e8400-e29b-41d4-a716-446655440000",
        "sk_test_secret",
        failingFetch,
      ),
    RevenueCatApiError,
  );
});
