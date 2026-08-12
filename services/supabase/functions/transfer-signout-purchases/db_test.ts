import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import {
  completeSignoutPurchaseHandoff,
  issueSignoutPurchaseHandoff,
  mapDatabaseError,
  readSignoutPurchaseSourceEntitlement,
  SignoutPurchaseHandoffDatabaseError,
} from "./db.ts";

const SOURCE_ID = "550e8400-e29b-41d4-a716-446655440001";

Deno.test("issue handoff forwards only the Edge-derived source and server snapshot", async () => {
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const admin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcName = name;
      rpcArguments = args;
      return Promise.resolve({
        data: [{
          handoff_id: "550e8400-e29b-41d4-a716-446655440002",
          expires_at: "2026-09-10T00:00:00.000Z",
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const result = await issueSignoutPurchaseHandoff(
    admin,
    SOURCE_ID,
    "a".repeat(64),
    1_786_500_000_000,
    { targetTier: "pro", expiresAt: "2027-08-01T00:00:00.000Z" },
  );

  assertEquals(rpcName, "issue_signout_purchase_handoff");
  assertEquals(rpcArguments, {
    p_source_user_id: SOURCE_ID,
    p_secret_hash: "a".repeat(64),
    p_source_snapshot_at_ms: 1_786_500_000_000,
    p_expected_store_tier: "pro",
    p_expected_store_expires_at: "2027-08-01T00:00:00.000Z",
  });
  assertEquals(
    result.handoffId,
    "550e8400-e29b-41d4-a716-446655440002",
  );
});

Deno.test("source entitlement read validates the exact durable projection", async () => {
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
    await readSignoutPurchaseSourceEntitlement(admin, SOURCE_ID),
    { targetTier: "pro", expiresAt: "2027-08-01T00:00:00.000Z" },
  );
  assertEquals(calls, [
    ["from", "users"],
    ["select", "subscription_tier,subscription_expires_at"],
    ["eq:id", SOURCE_ID],
    ["limit", 1],
  ]);
});

Deno.test("database errors distinguish terminal, conflict, and retryable proofs", async () => {
  const error = (
    message: string,
    code = "P0001",
  ) => ({ message, code } as PostgrestError);

  assertEquals(
    mapDatabaseError(error("signout_handoff_expired"), "fallback").code,
    "handoff_expired",
  );
  assertEquals(
    mapDatabaseError(
      error("signout_handoff_not_cancelable", "55000"),
      "fallback",
    ).code,
    "handoff_not_cancelable",
  );
  assertEquals(
    mapDatabaseError(error("serialization", "40001"), "fallback").code,
    "handoff_temporarily_unavailable",
  );

  const malformedAdmin = {
    from: () => ({
      select() {
        return this;
      },
      eq() {
        return this;
      },
      limit: () =>
        Promise.resolve({
          data: [{
            subscription_tier: "free",
            subscription_expires_at: "2027-08-01T00:00:00.000Z",
          }],
          error: null,
        }),
    }),
  } as unknown as SupabaseClient;
  await assertRejects(
    () => readSignoutPurchaseSourceEntitlement(malformedAdmin, SOURCE_ID),
    SignoutPurchaseHandoffDatabaseError,
  );
});

Deno.test("service completion forwards the exact destination snapshot and StoreKit state", async () => {
  let rpcName = "";
  let rpcArguments: Record<string, unknown> = {};
  const admin = {
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcName = name;
      rpcArguments = args;
      return Promise.resolve({
        data: [{
          handoff_id: "550e8400-e29b-41d4-a716-446655440002",
          completed_at: "2026-08-12T00:00:00.000Z",
          already_completed: false,
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  await completeSignoutPurchaseHandoff(
    admin,
    "550e8400-e29b-41d4-a716-446655440002",
    "b".repeat(64),
    "550e8400-e29b-41d4-a716-446655440003",
    1_786_500_000_000,
    { targetTier: "pro", expiresAt: "2027-08-01T00:00:00.000Z" },
  );

  assertEquals(rpcName, "complete_signout_purchase_handoff");
  assertEquals(rpcArguments, {
    p_handoff_id: "550e8400-e29b-41d4-a716-446655440002",
    p_secret_hash: "b".repeat(64),
    p_destination_user_id: "550e8400-e29b-41d4-a716-446655440003",
    p_destination_snapshot_at_ms: 1_786_500_000_000,
    p_destination_store_tier: "pro",
    p_destination_store_expires_at: "2027-08-01T00:00:00.000Z",
  });
});
