import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import {
  AccountDeletionIntakeError,
  AccountDeletionRecoveryError,
  prepareAccountDeletionRecoveryV2,
  recoverAccountDeletion,
  recoverAccountDeletionV2,
  requestAccountDeletion,
  requestAccountDeletionV2,
} from "./db.ts";

const USER_ID = "00000000-0000-0000-0000-00000000d201";
const JOB_ID = "00000000-0000-0000-0000-00000000d202";
const HASH = "a".repeat(64);
const ACK_HASH = "b".repeat(64);
const EXPIRES_AT = "2027-02-09T00:00:00.000Z";

type RpcResult = { data: unknown; error: { message: string } | null };

function client(
  rpc: (name: string, args: Record<string, unknown>) => Promise<RpcResult>,
): SupabaseClient {
  return { rpc } as unknown as SupabaseClient;
}

Deno.test("deletion intake selects the atomic recovery RPC only when a hash exists", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = client((name, args) => {
    calls.push({ name, args });
    return Promise.resolve({
      data: [{
        job_id: JOB_ID,
        job_status: "pending",
        manual_provider_revocation_required: false,
        ...(name === "request_account_deletion_with_recovery"
          ? { recovery_expires_at: EXPIRES_AT }
          : {}),
      }],
      error: null,
    });
  });

  const legacy = await requestAccountDeletion(USER_ID, supabase);
  const recoverable = await requestAccountDeletion(USER_ID, supabase, HASH);

  assertEquals(legacy.recoveryExpiresAt, null);
  assertEquals(recoverable.recoveryExpiresAt, EXPIRES_AT);
  assertEquals(calls, [
    {
      name: "request_account_deletion",
      args: { p_user_id: USER_ID },
    },
    {
      name: "request_account_deletion_with_recovery",
      args: { p_user_id: USER_ID, p_secret_hash: HASH },
    },
  ]);
});

Deno.test("capability recovery validates its identity-free receipt", async () => {
  const supabase = client((name, args) => {
    assertEquals(name, "recover_account_deletion");
    assertEquals(args, { p_secret_hash: HASH, p_acknowledge: true });
    return Promise.resolve({
      data: [{
        deletion_status: "completed",
        manual_provider_revocation_required: true,
        recovery_expires_at: EXPIRES_AT,
        recovery_acknowledged: true,
      }],
      error: null,
    });
  });

  assertEquals(await recoverAccountDeletion(supabase, HASH, true), {
    status: "completed",
    manualProviderRevocationRequired: true,
    recoveryExpiresAt: EXPIRES_AT,
    recoveryAcknowledged: true,
  });
});

Deno.test("protocol v2 prepares before commit and separates acknowledgement", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = client((name, args) => {
    calls.push({ name, args });
    if (name === "prepare_account_deletion_recovery_v2") {
      return Promise.resolve({
        data: [{
          recovery_prepared: true,
          recovery_expires_at: EXPIRES_AT,
        }],
        error: null,
      });
    }
    if (name === "request_account_deletion_with_recovery_v2") {
      return Promise.resolve({
        data: [{
          job_id: JOB_ID,
          job_status: "pending",
          manual_provider_revocation_required: false,
          recovery_expires_at: EXPIRES_AT,
        }],
        error: null,
      });
    }
    return Promise.resolve({
      data: [{
        deletion_status: name === "recover_account_deletion_v2"
          ? "not_committed"
          : "completed",
        manual_provider_revocation_required: false,
        recovery_expires_at: EXPIRES_AT,
        recovery_acknowledged:
          name === "acknowledge_account_deletion_recovery_v2",
      }],
      error: null,
    });
  });

  assertEquals(
    await prepareAccountDeletionRecoveryV2(
      USER_ID,
      supabase,
      HASH,
      ACK_HASH,
    ),
    { prepared: true, recoveryExpiresAt: EXPIRES_AT },
  );
  assertEquals(
    (await requestAccountDeletionV2(USER_ID, supabase, HASH)).jobId,
    JOB_ID,
  );
  assertEquals(
    (await recoverAccountDeletionV2(supabase, HASH, "recover")).status,
    "not_committed",
  );
  assertEquals(
    (await recoverAccountDeletionV2(supabase, ACK_HASH, "acknowledge"))
      .recoveryAcknowledged,
    true,
  );
  assertEquals(calls.map((call) => call.name), [
    "prepare_account_deletion_recovery_v2",
    "request_account_deletion_with_recovery_v2",
    "recover_account_deletion_v2",
    "acknowledge_account_deletion_recovery_v2",
  ]);
  assertEquals(calls[2].args, { p_recovery_secret_hash: HASH });
  assertEquals(calls[3].args, {
    p_acknowledgement_secret_hash: ACK_HASH,
  });
});

Deno.test("recovery maps invalid, expired, and unavailable database outcomes", async () => {
  for (
    const expected of [
      {
        message: "account_deletion_recovery_invalid",
        code: "account_deletion_recovery_invalid",
        status: 404,
      },
      {
        message: "account_deletion_recovery_expired",
        code: "account_deletion_recovery_expired",
        status: 410,
      },
      {
        message: "database offline for a private job",
        code: "account_deletion_recovery_unavailable",
        status: 503,
      },
    ]
  ) {
    const supabase = client(() =>
      Promise.resolve({ data: null, error: { message: expected.message } })
    );
    const error = await assertRejects(
      () => recoverAccountDeletion(supabase, HASH, false),
      AccountDeletionRecoveryError,
    );
    assertEquals(error.code, expected.code);
    assertEquals(error.status, expected.status);
    assertEquals(error.message.includes("private job"), false);
  }
});

Deno.test("expired v2 preparation state stays distinct from an accepted capability expiry", async () => {
  const fromReceipt = client(() =>
    Promise.resolve({
      data: [{
        deletion_status: "preparation_expired",
        manual_provider_revocation_required: false,
        recovery_expires_at: EXPIRES_AT,
        recovery_acknowledged: false,
      }],
      error: null,
    })
  );
  const receiptError = await assertRejects(
    () => recoverAccountDeletionV2(fromReceipt, HASH, "recover"),
    AccountDeletionRecoveryError,
  );
  assertEquals(
    receiptError.code,
    "account_deletion_recovery_preparation_expired",
  );
  assertEquals(receiptError.status, 410);

  const fromDatabaseError = client(() =>
    Promise.resolve({
      data: null,
      error: { message: "account_deletion_recovery_preparation_expired" },
    })
  );
  const databaseError = await assertRejects(
    () => recoverAccountDeletionV2(fromDatabaseError, HASH, "recover"),
    AccountDeletionRecoveryError,
  );
  assertEquals(
    databaseError.code,
    "account_deletion_recovery_preparation_expired",
  );
  assertEquals(databaseError.status, 410);

  const rejectedCommit = client(() =>
    Promise.resolve({
      data: null,
      error: { message: "account_deletion_recovery_preparation_expired" },
    })
  );
  const commitError = await assertRejects(
    () => requestAccountDeletionV2(USER_ID, rejectedCommit, HASH),
    AccountDeletionIntakeError,
  );
  assertEquals(
    commitError.code,
    "account_deletion_recovery_preparation_expired",
  );
  assertEquals(commitError.status, 410);
});
