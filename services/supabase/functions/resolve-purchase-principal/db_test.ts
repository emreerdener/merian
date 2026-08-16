import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import {
  beginPurchasePrincipalResolution,
  cancelPurchasePrincipalSignoutRotation,
  claimPurchasePrincipalSignoutRotation,
  completePurchasePrincipalResolution,
  preparePurchasePrincipalSignoutRotation,
  PurchasePrincipalDatabaseError,
  readCurrentEntitlementProjection,
} from "./db.ts";

const AUTH_USER_ID = "550e8400-e29b-41d4-a716-446655440000";
const PRINCIPAL_ID = "650e8400-e29b-41d4-a716-446655440000";
const CAPABILITY_HASH = "a".repeat(64);
const SECRET_HASH = "b".repeat(64);
const APP_USER_ID = "MERIAN_PP_00112233445566778899AABBCCDDEEFF";

function rpcClient(
  data: unknown,
  error: { message: string; code?: string } | null = null,
  calls: Array<{ name: string; args?: Record<string, unknown> }> = [],
): SupabaseClient {
  return {
    rpc(name: string, args?: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({ data, error });
    },
  } as unknown as SupabaseClient;
}

Deno.test("begin resolution returns explicit legacy compatibility", async () => {
  const calls: Array<{ name: string; args?: Record<string, unknown> }> = [];
  const result = await beginPurchasePrincipalResolution(
    rpcClient(
      [{
        resolution_mode: "legacy",
        purchase_principal_id: null,
        revenuecat_app_user_id: null,
        minimum_client_protocol: 1,
        requires_attestation: false,
        binding_intent_generation: null,
        allow_non_subscription_pass_grant: null,
      }],
      null,
      calls,
    ),
    AUTH_USER_ID,
    CAPABILITY_HASH,
    1,
    7,
  );

  assertEquals(result, { mode: "legacy", minimumClientProtocol: 1 });
  assertEquals(calls, [{
    name: "begin_purchase_principal_resolution",
    args: {
      p_auth_user_id: AUTH_USER_ID,
      p_capability_hash: CAPABILITY_HASH,
      p_client_protocol: 1,
      p_binding_intent_generation: 7,
    },
  }]);
});

Deno.test("begin resolution returns the durable pass policy for an active principal", async () => {
  const result = await beginPurchasePrincipalResolution(
    rpcClient([{
      resolution_mode: "stable",
      purchase_principal_id: PRINCIPAL_ID,
      revenuecat_app_user_id: APP_USER_ID,
      minimum_client_protocol: 1,
      requires_attestation: true,
      binding_intent_generation: 7,
      allow_non_subscription_pass_grant: false,
    }]),
    AUTH_USER_ID,
    CAPABILITY_HASH,
    1,
    7,
  );

  assertEquals(result, {
    mode: "stable",
    purchasePrincipalId: PRINCIPAL_ID,
    revenueCatAppUserId: APP_USER_ID,
    minimumClientProtocol: 1,
    bindingIntentGeneration: 7,
    allowNonSubscriptionPassGrant: false,
  });
});

Deno.test("stable resolution completion validates continuity and exact state", async () => {
  const start = {
    mode: "stable" as const,
    purchasePrincipalId: PRINCIPAL_ID,
    revenueCatAppUserId: APP_USER_ID,
    minimumClientProtocol: 1,
    bindingIntentGeneration: 7,
    allowNonSubscriptionPassGrant: null,
  };
  const calls: Array<{ name: string; args?: Record<string, unknown> }> = [];
  const result = await completePurchasePrincipalResolution(
    rpcClient(
      [{
        purchase_principal_id: PRINCIPAL_ID,
        revenuecat_app_user_id: APP_USER_ID,
        binding_generation: 2,
        account_grants_allowed: false,
        already_bound: false,
      }],
      null,
      calls,
    ),
    AUTH_USER_ID,
    start,
    CAPABILITY_HASH,
    1_786_500_000_000,
    { targetTier: "pro", expiresAt: "2027-08-01T00:00:00.000Z" },
    true,
    { targetTier: "free", expiresAt: null },
  );

  assertEquals(result, {
    purchasePrincipalId: PRINCIPAL_ID,
    revenueCatAppUserId: APP_USER_ID,
    bindingGeneration: 2,
    accountGrantsAllowed: false,
    alreadyBound: false,
  });
  assertEquals(calls[0], {
    name: "complete_purchase_principal_resolution",
    args: {
      p_auth_user_id: AUTH_USER_ID,
      p_purchase_principal_id: PRINCIPAL_ID,
      p_capability_hash: CAPABILITY_HASH,
      p_binding_intent_generation: 7,
      p_authoritative_snapshot_at_ms: 1_786_500_000_000,
      p_store_tier: "pro",
      p_store_expires_at: "2027-08-01T00:00:00.000Z",
      p_allow_non_subscription_pass_grant: true,
      p_account_grant_tier: "free",
      p_account_grant_expires_at: null,
    },
  });

  await assertRejects(
    () =>
      completePurchasePrincipalResolution(
        rpcClient([{
          purchase_principal_id: PRINCIPAL_ID,
          revenuecat_app_user_id: "different",
          binding_generation: 2,
          account_grants_allowed: false,
          already_bound: true,
        }]),
        AUTH_USER_ID,
        start,
        CAPABILITY_HASH,
        1,
        { targetTier: "free", expiresAt: null },
        false,
        { targetTier: "free", expiresAt: null },
      ),
    PurchasePrincipalDatabaseError,
    "stable identity continuity",
  );
});

Deno.test("stable sign-out rotation RPCs preserve exact proof and identity fields", async () => {
  const rotationId = "750e8400-e29b-41d4-a716-446655440000";
  const calls: Array<{ name: string; args?: Record<string, unknown> }> = [];
  const preparation = await preparePurchasePrincipalSignoutRotation(
    rpcClient(
      [{
        rotation_id: rotationId,
        purchase_principal_id: PRINCIPAL_ID,
        revenuecat_app_user_id: APP_USER_ID,
        binding_generation: 4,
        rotation_status: "prepared",
        expires_at: "2026-09-15T00:00:00.000Z",
        already_prepared: false,
      }],
      null,
      calls,
    ),
    AUTH_USER_ID,
    CAPABILITY_HASH,
    rotationId,
    SECRET_HASH,
    4,
    3,
  );
  assertEquals(preparation.rotationId, rotationId);
  assertEquals(calls[0], {
    name: "prepare_purchase_principal_signout_rotation",
    args: {
      p_auth_user_id: AUTH_USER_ID,
      p_capability_hash: CAPABILITY_HASH,
      p_rotation_id: rotationId,
      p_secret_hash: SECRET_HASH,
      p_expected_binding_generation: 4,
      p_client_protocol: 3,
    },
  });

  const claim = await claimPurchasePrincipalSignoutRotation(
    rpcClient([{
      rotation_id: rotationId,
      purchase_principal_id: PRINCIPAL_ID,
      revenuecat_app_user_id: APP_USER_ID,
      binding_generation: 5,
      account_grants_allowed: false,
      rotation_status: "completed",
      expires_at: "2026-09-15T00:00:00.000Z",
      already_claimed: false,
    }]),
    AUTH_USER_ID,
    CAPABILITY_HASH,
    rotationId,
    SECRET_HASH,
    3,
  );
  assertEquals(claim.purchasePrincipalId, PRINCIPAL_ID);
  assertEquals(claim.bindingGeneration, 5);
  assertEquals(claim.accountGrantsAllowed, false);

  const cancellation = await cancelPurchasePrincipalSignoutRotation(
    rpcClient([{
      rotation_id: rotationId,
      rotation_status: "cancelled",
      expires_at: "2026-09-15T00:00:00.000Z",
      already_cancelled: true,
    }]),
    AUTH_USER_ID,
    CAPABILITY_HASH,
    rotationId,
    SECRET_HASH,
    3,
  );
  assertEquals(cancellation.status, "cancelled");
  assertEquals(cancellation.alreadyCancelled, true);
});

Deno.test("expired rotation claims are terminal and ordinary resolution interlocks do not retry", async () => {
  const rotationId = "750e8400-e29b-41d4-a716-446655440000";
  const expired = await assertRejects(
    () =>
      claimPurchasePrincipalSignoutRotation(
        rpcClient([{
          rotation_id: rotationId,
          purchase_principal_id: PRINCIPAL_ID,
          revenuecat_app_user_id: APP_USER_ID,
          binding_generation: null,
          account_grants_allowed: false,
          rotation_status: "expired",
          expires_at: "2026-09-15T00:00:00.000Z",
          already_claimed: false,
        }]),
        AUTH_USER_ID,
        CAPABILITY_HASH,
        rotationId,
        SECRET_HASH,
        3,
      ),
    PurchasePrincipalDatabaseError,
  );
  assertEquals(expired.code, "purchase_principal_signout_rotation_expired");
  assertEquals(expired.retryable, false);

  const interlock = await assertRejects(
    () =>
      beginPurchasePrincipalResolution(
        rpcClient(null, {
          message: "purchase_principal_signout_rotation_required",
          code: "55P03",
        }),
        AUTH_USER_ID,
        CAPABILITY_HASH,
        3,
        8,
      ),
    PurchasePrincipalDatabaseError,
  );
  assertEquals(interlock.retryable, false);
});

Deno.test("entitlement projection read validates one exact server row", async () => {
  const calls: Array<[string, unknown]> = [];
  const builder = {
    select(columns: string) {
      calls.push(["select", columns]);
      return this;
    },
    eq(column: string, value: unknown) {
      calls.push([`eq:${column}`, value]);
      return this;
    },
    limit(limit: number) {
      calls.push(["limit", limit]);
      return Promise.resolve({
        data: [{
          subscription_tier: "pro",
          subscription_expires_at: "2027-08-01T00:00:00.000Z",
        }],
        error: null,
      });
    },
  };
  const admin = {
    from(table: string) {
      calls.push(["from", table]);
      return builder;
    },
  } as unknown as SupabaseClient;

  assertEquals(
    await readCurrentEntitlementProjection(admin, AUTH_USER_ID),
    { targetTier: "pro", expiresAt: "2027-08-01T00:00:00.000Z" },
  );
  assertEquals(calls, [
    ["from", "users"],
    ["select", "subscription_tier,subscription_expires_at"],
    ["eq:id", AUTH_USER_ID],
    ["limit", 1],
  ]);
});

Deno.test("database failures classify revoked capabilities as terminal", async () => {
  const error = await assertRejects(
    () =>
      beginPurchasePrincipalResolution(
        rpcClient(null, {
          message: "purchase_principal_capability_revoked",
          code: "42501",
        }),
        AUTH_USER_ID,
        CAPABILITY_HASH,
        1,
        7,
      ),
    PurchasePrincipalDatabaseError,
  );
  assertEquals(error.code, "purchase_principal_capability_revoked");
  assertEquals(error.retryable, false);
});

Deno.test("database failures preserve the client-upgrade code", async () => {
  const error = await assertRejects(
    () =>
      beginPurchasePrincipalResolution(
        rpcClient(null, {
          message: "purchase_principal_client_upgrade_required",
          code: "22023",
        }),
        AUTH_USER_ID,
        CAPABILITY_HASH,
        1,
        7,
      ),
    PurchasePrincipalDatabaseError,
  );
  assertEquals(error.code, "purchase_principal_client_upgrade_required");
  assertEquals(error.retryable, false);
});

Deno.test("database failures preserve the account-deletion interlock", async () => {
  const error = await assertRejects(
    () =>
      beginPurchasePrincipalResolution(
        rpcClient(null, {
          message: "purchase_principal_account_deletion_in_progress",
          code: "P0002",
        }),
        AUTH_USER_ID,
        CAPABILITY_HASH,
        1,
        7,
      ),
    PurchasePrincipalDatabaseError,
  );
  assertEquals(
    error.code,
    "purchase_principal_account_deletion_in_progress",
  );
  assertEquals(error.retryable, true);
});
