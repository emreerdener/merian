import type { SupabaseClient, User } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import { SEVEN_DAY_PASS_PRODUCT_ID } from "../_shared/subscriptionPass.ts";
import type { PurchasePrincipalResolutionStart } from "./db.ts";
import { PurchasePrincipalDatabaseError } from "./db.ts";
import { handleResolvePurchasePrincipal } from "./handler.ts";
import { PURCHASE_PRINCIPAL_CLIENT_PROTOCOL } from "./protocol.ts";

const NOW_MS = 1_786_500_000_000;
const AUTH_USER_ID = "550e8400-e29b-41d4-a716-446655440000";
const PRINCIPAL_ID = "650e8400-e29b-41d4-a716-446655440000";
const APP_USER_ID = "MERIAN_PP_00112233445566778899AABBCCDDEEFF";
const CAPABILITY = "A".repeat(43);
const supabaseAdmin = {} as SupabaseClient;

function request(body: Record<string, unknown> = {}): Request {
  return new Request("https://example.test/resolve-purchase-principal", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      operation: "resolve",
      installation_capability: CAPABILITY,
      client_protocol: PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
      binding_intent_generation: 7,
      ...body,
    }),
  });
}

function user(): User {
  return { id: AUTH_USER_ID, is_anonymous: false } as User;
}

function stableStart(
  allowNonSubscriptionPassGrant: boolean | null = null,
): Extract<
  PurchasePrincipalResolutionStart,
  { mode: "stable" }
> {
  return {
    mode: "stable",
    purchasePrincipalId: PRINCIPAL_ID,
    revenueCatAppUserId: APP_USER_ID,
    minimumClientProtocol: PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
    bindingIntentGeneration: 7,
    allowNonSubscriptionPassGrant,
  };
}

Deno.test("legacy mode returns without reading RevenueCat", async () => {
  let providerFetchCount = 0;
  const response = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      begin: () =>
        Promise.resolve({ mode: "legacy", minimumClientProtocol: 1 }),
      fetchCustomerInfo: () => {
        providerFetchCount += 1;
        return Promise.reject(new Error("must not fetch"));
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(await response.json(), {
    success: true,
    mode: "legacy",
    minimum_client_protocol: 1,
  });
  assertEquals(providerFetchCount, 0);
});

Deno.test("stable mode separates StoreKit state from account promotions", async () => {
  const seen: Record<string, unknown>[] = [];
  const response = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      begin: () => Promise.resolve(stableStart()),
      fetchCustomerInfo: (appUserId) => {
        assertEquals(appUserId, APP_USER_ID);
        return Promise.resolve({
          requestDateMs: NOW_MS,
          subscriber: {
            entitlements: {
              pro: {
                product_identifier: "merian_pro_annual",
                expires_date: "2027-08-01T00:00:00.000Z",
              },
              "Naturalist Tier": {
                product_identifier: "operator_beta",
                expires_date: "2026-10-01T00:00:00.000Z",
              },
            },
            subscriptions: {
              merian_pro_annual: { store: "app_store" },
              operator_beta: { store: "promotional" },
            },
            non_subscriptions: {},
          },
        });
      },
      complete: (
        _admin,
        authUserId,
        start,
        capabilityHash,
        snapshotAtMs,
        storeState,
        allowNonSubscriptionPassGrant,
        accountGrantState,
      ) => {
        seen.push({
          authUserId,
          start,
          capabilityHash,
          snapshotAtMs,
          storeState,
          allowNonSubscriptionPassGrant,
          accountGrantState,
        });
        return Promise.resolve({
          purchasePrincipalId: PRINCIPAL_ID,
          revenueCatAppUserId: APP_USER_ID,
          bindingGeneration: 3,
          accountGrantsAllowed: false,
          alreadyBound: false,
        });
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    success: true,
    mode: "stable",
    purchase_principal_id: PRINCIPAL_ID,
    revenuecat_app_user_id: APP_USER_ID,
    binding_generation: 3,
    account_grants_allowed: false,
    minimum_client_protocol: PURCHASE_PRINCIPAL_CLIENT_PROTOCOL,
  });
  assertEquals(seen.length, 1);
  assertEquals(seen[0].authUserId, AUTH_USER_ID);
  assertEquals(seen[0].snapshotAtMs, NOW_MS);
  assertEquals(seen[0].storeState, {
    targetTier: "pro",
    expiresAt: "2027-08-01T00:00:00.000Z",
  });
  assertEquals(seen[0].allowNonSubscriptionPassGrant, false);
  assertEquals(seen[0].accountGrantState, {
    targetTier: "pro",
    expiresAt: "2026-10-01T00:00:00.000Z",
  });
  assertEquals(
    typeof seen[0].capabilityHash === "string" &&
      /^[0-9a-f]{64}$/.test(seen[0].capabilityHash as string),
    true,
  );
});

Deno.test("first stable adoption authorizes a detached pass only from the exact server projection", async () => {
  const passExpiry = "2026-08-17T00:00:00.000Z";
  const customerInfo = {
    requestDateMs: NOW_MS,
    subscriber: {
      entitlements: {},
      subscriptions: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "pass-transaction",
          purchase_date: "2026-08-10T00:00:00.000Z",
          store: "app_store",
        }],
      },
    },
  };
  const completions: Array<Record<string, unknown>> = [];

  const response = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      begin: () => Promise.resolve(stableStart()),
      fetchCustomerInfo: () => Promise.resolve(customerInfo),
      readCurrentEntitlement: () =>
        Promise.resolve({ targetTier: "pro", expiresAt: passExpiry }),
      complete: (
        _admin,
        _authUserId,
        _start,
        _capabilityHash,
        _snapshotAtMs,
        storeState,
        allowNonSubscriptionPassGrant,
      ) => {
        completions.push({ storeState, allowNonSubscriptionPassGrant });
        return Promise.resolve({
          purchasePrincipalId: PRINCIPAL_ID,
          revenueCatAppUserId: APP_USER_ID,
          bindingGeneration: 1,
          accountGrantsAllowed: false,
          alreadyBound: false,
        });
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(completions, [{
    storeState: { targetTier: "pro", expiresAt: passExpiry },
    allowNonSubscriptionPassGrant: true,
  }]);
});

Deno.test("mismatched projection and an active false policy cannot resurrect pass history", async () => {
  const customerInfo = {
    requestDateMs: NOW_MS,
    subscriber: {
      entitlements: {},
      subscriptions: {},
      non_subscriptions: {
        [SEVEN_DAY_PASS_PRODUCT_ID]: [{
          id: "historical-pass",
          purchase_date: "2026-08-10T00:00:00.000Z",
          store: "app_store",
        }],
      },
    },
  };

  for (
    const scenario of [
      { start: stableStart(), expectedProjectionReads: 1 },
      { start: stableStart(false), expectedProjectionReads: 0 },
    ]
  ) {
    let projectionReads = 0;
    const completions: Array<Record<string, unknown>> = [];
    const response = await handleResolvePurchasePrincipal(
      request(),
      user(),
      supabaseAdmin,
      {
        apiKey: "sk_test",
        now: () => NOW_MS,
        begin: () => Promise.resolve(scenario.start),
        fetchCustomerInfo: () => Promise.resolve(customerInfo),
        readCurrentEntitlement: () => {
          projectionReads += 1;
          return Promise.resolve({ targetTier: "free", expiresAt: null });
        },
        complete: (
          _admin,
          _authUserId,
          _start,
          _capabilityHash,
          _snapshotAtMs,
          storeState,
          allowNonSubscriptionPassGrant,
        ) => {
          completions.push({ storeState, allowNonSubscriptionPassGrant });
          return Promise.resolve({
            purchasePrincipalId: PRINCIPAL_ID,
            revenueCatAppUserId: APP_USER_ID,
            bindingGeneration: 2,
            accountGrantsAllowed: false,
            alreadyBound: true,
          });
        },
      },
    );

    assertEquals(response.status, 200);
    assertEquals(projectionReads, scenario.expectedProjectionReads);
    assertEquals(completions, [{
      storeState: { targetTier: "free", expiresAt: null },
      allowNonSubscriptionPassGrant: false,
    }]);
  }
});

Deno.test("stable mode fails closed on configuration and stale snapshots", async () => {
  let completeCount = 0;
  const missingKey = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      apiKey: "",
      begin: () => Promise.resolve(stableStart()),
    },
  );
  assertEquals(missingKey.status, 503);
  assertEquals(
    (await missingKey.json()).code,
    "purchase_principal_unavailable",
  );

  const stale = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      apiKey: "sk_test",
      now: () => NOW_MS,
      begin: () => Promise.resolve(stableStart()),
      fetchCustomerInfo: () =>
        Promise.resolve({
          requestDateMs: NOW_MS - 16 * 60 * 1_000,
          subscriber: {},
        }),
      complete: () => {
        completeCount += 1;
        throw new Error("must not complete");
      },
    },
  );
  assertEquals(stale.status, 503);
  assertEquals(completeCount, 0);
});

Deno.test("revoked installation capability is a terminal conflict", async () => {
  const response = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      begin: () =>
        Promise.reject(
          new PurchasePrincipalDatabaseError(
            "purchase_principal_capability_revoked",
            false,
            "revoked",
          ),
        ),
    },
  );

  assertEquals(response.status, 409);
  assertEquals(
    (await response.json()).code,
    "purchase_principal_capability_revoked",
  );
});

Deno.test("an activated principal requiring a newer client fails closed", async () => {
  const logs: string[] = [];
  const originalError = console.error;
  console.error = (...args: unknown[]) => logs.push(String(args[0]));
  let response: Response;
  try {
    response = await handleResolvePurchasePrincipal(
      request(),
      user(),
      supabaseAdmin,
      {
        begin: () =>
          Promise.reject(
            new PurchasePrincipalDatabaseError(
              "purchase_principal_client_upgrade_required",
              false,
              "upgrade required",
            ),
          ),
      },
    );
  } finally {
    console.error = originalError;
  }

  assertEquals(response.status, 426);
  assertEquals(
    (await response.json()).code,
    "purchase_principal_client_upgrade_required",
  );
  assertEquals(logs.length, 1);
  assertEquals(JSON.parse(logs[0]).status, 426);
});

Deno.test("account deletion in progress is a retryable fail-closed response", async () => {
  const response = await handleResolvePurchasePrincipal(
    request(),
    user(),
    supabaseAdmin,
    {
      begin: () =>
        Promise.reject(
          new PurchasePrincipalDatabaseError(
            "purchase_principal_account_deletion_in_progress",
            true,
            "account deletion in progress",
          ),
        ),
    },
  );

  assertEquals(response.status, 503);
  assertEquals(
    (await response.json()).code,
    "purchase_principal_account_deletion_in_progress",
  );
});
