import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import { AccountDeletionRecoveryError } from "../safe-delete/db.ts";
import { handleAccountDeletionRecovery } from "./handler.ts";

const CAPABILITY = "A".repeat(43);
const CAPABILITY_HASH =
  "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a";
const V2_RECOVERY_HASH =
  "645e4eada850b504783b4735ad1260bd60c61e4ed7f245075a463a2c7e651c58";
const V2_ACKNOWLEDGEMENT_HASH =
  "647623a2ed61d3b776ed90aea5eae2b9f5ec1fc8ff00af18a53bd9ded6e4ed26";
const EXPIRES_AT = "2027-02-09T00:00:00.000Z";
const supabaseAdmin = {} as SupabaseClient;

function request(
  operation: "recover" | "acknowledge",
  capability = CAPABILITY,
): Request {
  return new Request("https://example.test/recover-account-deletion", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      operation,
      recovery_capability: capability,
    }),
  });
}

function v2Request(
  operation: "recover" | "acknowledge",
  capability = CAPABILITY,
): Request {
  return new Request("https://example.test/recover-account-deletion", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      protocol_version: 2,
      operation,
      ...(operation === "recover"
        ? { recovery_capability: capability }
        : { acknowledgement_capability: capability }),
    }),
  });
}

Deno.test("recovery hashes the proof and returns no deletion identity", async () => {
  const calls: Array<{ hash: string; acknowledge: boolean }> = [];
  const response = await handleAccountDeletionRecovery(
    request("recover"),
    supabaseAdmin,
    {
      recover: (_admin, hash, acknowledge) => {
        calls.push({ hash, acknowledge });
        return Promise.resolve({
          status: "pending",
          manualProviderRevocationRequired: false,
          recoveryExpiresAt: EXPIRES_AT,
          recoveryAcknowledged: false,
        });
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  assertEquals(calls, [{ hash: CAPABILITY_HASH, acknowledge: false }]);
  assertEquals(await response.json(), {
    success: true,
    status: "pending",
    manual_provider_revocation_required: false,
    recovery_capability_expires_at: EXPIRES_AT,
    recovery_acknowledged: false,
  });
});

Deno.test("acknowledge is capability-only and idempotent", async () => {
  let acknowledged = false;
  const response = await handleAccountDeletionRecovery(
    request("acknowledge"),
    supabaseAdmin,
    {
      recover: (_admin, hash, acknowledge) => {
        assertEquals(hash, CAPABILITY_HASH);
        acknowledged = acknowledge;
        return Promise.resolve({
          status: "completed",
          manualProviderRevocationRequired: true,
          recoveryExpiresAt: EXPIRES_AT,
          recoveryAcknowledged: true,
        });
      },
    },
  );

  assertEquals(acknowledged, true);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).recovery_acknowledged, true);
});

Deno.test("v2 prepared recovery is terminal without claiming deletion", async () => {
  const calls: Array<{ hash: string; operation: string }> = [];
  const response = await handleAccountDeletionRecovery(
    v2Request("recover"),
    supabaseAdmin,
    {
      recoverV2: (_admin, hash, operation) => {
        calls.push({ hash, operation });
        return Promise.resolve({
          status: "not_committed",
          manualProviderRevocationRequired: false,
          recoveryExpiresAt: EXPIRES_AT,
          recoveryAcknowledged: false,
        });
      },
    },
  );

  assertEquals(calls, [{ hash: V2_RECOVERY_HASH, operation: "recover" }]);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    success: true,
    status: "not_committed",
    protocol_version: 2,
    manual_provider_revocation_required: false,
    recovery_capability_expires_at: EXPIRES_AT,
    recovery_acknowledged: false,
  });
});

Deno.test("v2 acknowledgement uses only its independent capability", async () => {
  let operation: string | undefined;
  const response = await handleAccountDeletionRecovery(
    v2Request("acknowledge"),
    supabaseAdmin,
    {
      recoverV2: (_admin, hash, requestedOperation) => {
        assertEquals(hash, V2_ACKNOWLEDGEMENT_HASH);
        operation = requestedOperation;
        return Promise.resolve({
          status: "completed",
          manualProviderRevocationRequired: false,
          recoveryExpiresAt: EXPIRES_AT,
          recoveryAcknowledged: true,
        });
      },
    },
  );
  assertEquals(operation, "acknowledge");
  assertEquals(response.status, 200);
});

Deno.test("invalid and expired proofs expose only stable bounded errors", async () => {
  for (
    const expected of [
      {
        error: new AccountDeletionRecoveryError(
          "account_deletion_recovery_invalid",
          404,
          "Account deletion recovery is unavailable.",
        ),
        status: 404,
      },
      {
        error: new AccountDeletionRecoveryError(
          "account_deletion_recovery_expired",
          410,
          "Account deletion recovery has expired.",
        ),
        status: 410,
      },
      {
        error: new AccountDeletionRecoveryError(
          "account_deletion_recovery_preparation_expired",
          410,
          "Account deletion preparation expired before it could authorize recovery.",
        ),
        status: 410,
      },
    ]
  ) {
    const response = await handleAccountDeletionRecovery(
      request("recover"),
      supabaseAdmin,
      { recover: () => Promise.reject(expected.error) },
    );
    const body = await response.json();
    assertEquals(response.status, expected.status);
    assertEquals(body.code, expected.error.code);
    assertEquals(JSON.stringify(body).includes(CAPABILITY), false);
  }
});

Deno.test("malformed requests never reach the database", async () => {
  let called = false;
  const response = await handleAccountDeletionRecovery(
    request("recover", "short"),
    supabaseAdmin,
    {
      recover: () => {
        called = true;
        return Promise.reject(new Error("must not run"));
      },
    },
  );

  assertEquals(response.status, 400);
  assertEquals(called, false);
});

Deno.test("unexpected recovery failures remain fail-closed", async () => {
  await assertRejects(
    () =>
      handleAccountDeletionRecovery(
        request("recover"),
        supabaseAdmin,
        { recover: () => Promise.reject(new Error("database offline")) },
      ),
    Error,
    "database offline",
  );
});
