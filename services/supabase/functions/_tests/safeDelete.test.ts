import type { SupabaseClient } from "@supabase/supabase-js";
import { assert, assertEquals, assertRejects } from "@std/assert";
import type { AccountDeletionClaim } from "../safe-delete/db.ts";
import { handleSafeDelete } from "../safe-delete/handler.ts";
import { AccountDeletionIntakeError } from "../safe-delete/db.ts";
import { processAccountDeletionJobs } from "../safe-delete/worker.ts";

const supabaseAdmin = {} as SupabaseClient;
const preparationV2SuccessFixture = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "./fixtures/account-deletion-preparation-v2-success.json",
      import.meta.url,
    ),
  ),
) as Record<string, unknown>;

function pendingClaim(): AccountDeletionClaim {
  return {
    jobId: "00000000-0000-0000-0000-00000000d101",
    userId: "00000000-0000-0000-0000-00000000d102",
    status: "pending",
    claimToken: "00000000-0000-0000-0000-00000000d103",
    claimExpiresAt: "2026-07-25T04:00:00.000Z",
  };
}

Deno.test("safe-delete persists intent before cleanup and Auth deletion", async () => {
  const order: string[] = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    { targetUserId: pendingClaim().userId, limit: 1 },
    {
      claim: () => {
        order.push("claim");
        return Promise.resolve([pendingClaim()]);
      },
      cleanup: () => {
        order.push("cleanup");
        return Promise.resolve("auth_pending");
      },
      deleteAuth: () => {
        order.push("delete_auth");
        return Promise.resolve({ succeeded: true });
      },
      finish: (_client, _claim, authDeleted) => {
        order.push(authDeleted ? "complete" : "defer");
        return Promise.resolve();
      },
    },
  );

  assertEquals(order, ["claim", "cleanup", "delete_auth", "complete"]);
  assertEquals(result.completed, 1);
  assertEquals(result.deferred, 0);
});

Deno.test("cleanup failure never deletes the Auth identity", async () => {
  let authCalled = false;
  const finishes: boolean[] = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.reject(new Error("database unavailable")),
      deleteAuth: () => {
        authCalled = true;
        return Promise.resolve({ succeeded: true });
      },
      finish: (_client, _claim, authDeleted) => {
        finishes.push(authDeleted);
        return Promise.resolve();
      },
    },
  );

  assertEquals(authCalled, false);
  assertEquals(finishes, [false]);
  assertEquals(result.completed, 0);
  assertEquals(result.deferred, 1);
  assertEquals(result.failures[0]?.stage, "cleanup");
});

Deno.test("Auth failure is deferred only after cleanup commits", async () => {
  const order: string[] = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => {
        order.push("cleanup");
        return Promise.resolve("auth_pending");
      },
      deleteAuth: () => {
        order.push("delete_auth");
        return Promise.resolve({
          succeeded: false,
          errorCode: "auth_http_503",
        });
      },
      finish: (_client, _claim, authDeleted, errorCode) => {
        order.push(authDeleted ? "complete" : `defer:${errorCode}`);
        return Promise.resolve();
      },
    },
  );

  assertEquals(order, [
    "cleanup",
    "delete_auth",
    "defer:auth_http_503",
  ]);
  assertEquals(result.deferred, 1);
  assertEquals(result.failures[0]?.stage, "auth");
});

Deno.test("reclaimed auth_pending jobs revalidate cleanup before Auth", async () => {
  const order: string[] = [];
  const claim = { ...pendingClaim(), status: "auth_pending" as const };
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([claim]),
      cleanup: () => {
        order.push("cleanup");
        return Promise.resolve("auth_pending");
      },
      deleteAuth: () => {
        order.push("delete_auth");
        return Promise.resolve({ succeeded: true });
      },
      finish: () => {
        order.push("complete");
        return Promise.resolve();
      },
    },
  );

  assertEquals(order, ["cleanup", "delete_auth", "complete"]);
  assertEquals(result.completed, 1);
});

Deno.test("lost completion response leaves a retryable Auth-safe job", async () => {
  const finishCalls: boolean[] = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.resolve("auth_pending"),
      deleteAuth: () => Promise.resolve({ succeeded: true }),
      finish: (_client, _claim, authDeleted) => {
        finishCalls.push(authDeleted);
        if (authDeleted) {
          return Promise.reject(new Error("response lost"));
        }
        return Promise.resolve();
      },
    },
  );

  assertEquals(finishCalls, [true, false]);
  assertEquals(result.deferred, 1);
  assertEquals(result.failures[0]?.stage, "completion");
});

Deno.test("safe-delete handler records the job before its fast-path worker", async () => {
  const order: string[] = [];
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () => {
        order.push("request");
        return Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
          manualProviderRevocationRequired: false,
        });
      },
      process: () => {
        order.push("process");
        return Promise.resolve({
          claimed: 1,
          completed: 1,
          deferred: 0,
          waitingForStorage: 0,
          failures: [],
        });
      },
    },
  );

  assertEquals(order, ["request", "process"]);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    success: true,
    status: "completed",
    manual_provider_revocation_required: false,
    message: "Account securely deleted and anonymized.",
  });
});

Deno.test("safe-delete atomically threads a recovery hash into its receipt", async () => {
  const recoveryHash = "a".repeat(64);
  const expiresAt = "2027-02-09T00:00:00.000Z";
  let receivedHash: string | null | undefined;
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: (_userId, _admin, hash) => {
        receivedHash = hash;
        return Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "completed",
          manualProviderRevocationRequired: false,
          recoveryExpiresAt: expiresAt,
        });
      },
      process: () => {
        throw new Error("completed intake must not run the worker");
      },
    },
    recoveryHash,
  );

  assertEquals(receivedHash, recoveryHash);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    success: true,
    status: "completed",
    manual_provider_revocation_required: false,
    recovery_capability_expires_at: expiresAt,
    message: "Account securely deleted and anonymized.",
  });
});

Deno.test("safe-delete returns accepted after durable retry scheduling", async () => {
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () =>
        Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
          manualProviderRevocationRequired: false,
        }),
      process: () =>
        Promise.resolve({
          claimed: 1,
          completed: 0,
          deferred: 1,
          waitingForStorage: 0,
          failures: [{
            jobId: pendingClaim().jobId,
            stage: "cleanup",
            code: "cleanup_failed",
          }],
        }),
    },
  );

  assertEquals(response.status, 202);
  assertEquals((await response.json()).status, "pending");
});

Deno.test("safe-delete deferred diagnostics omit deletion identities and raw failures", async () => {
  const marker = "018f22a2-7c5c-7cc4-98c9-2e389f13f521";
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(String(args[0]));

  try {
    const response = await handleSafeDelete(
      pendingClaim().userId,
      supabaseAdmin,
      {
        request: () =>
          Promise.resolve({
            jobId: marker,
            status: "pending",
            manualProviderRevocationRequired: false,
          }),
        process: () =>
          Promise.resolve({
            claimed: 1,
            completed: 0,
            deferred: 1,
            waitingForStorage: 0,
            failures: [{
              jobId: marker,
              stage: "provider",
              code: `provider-customer-${marker}`,
            }],
          }),
      },
    );

    assertEquals(response.status, 202);
  } finally {
    console.error = original;
  }

  assertEquals(logs.length, 1);
  assert(logs[0].includes("account_deletion_attempt_deferred"));
  assert(logs[0].includes('"code":"operation_failed"'));
  assert(!logs[0].includes(marker));
  assert(!logs[0].includes("provider-customer"));
  assert(!logs[0].includes("job_id"));
});

Deno.test("safe-delete remains accepted if fast-path claiming fails", async () => {
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () =>
        Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
          manualProviderRevocationRequired: false,
        }),
      process: () => Promise.reject(new Error("database unavailable")),
    },
  );

  assertEquals(response.status, 202);
  assertEquals((await response.json()).status, "pending");
});

Deno.test("safe-delete does no destructive work if durable intake fails", async () => {
  let processCalled = false;
  await assertRejects(
    () =>
      handleSafeDelete(
        pendingClaim().userId,
        supabaseAdmin,
        {
          request: () => Promise.reject(new Error("intake failed")),
          process: () => {
            processCalled = true;
            return Promise.resolve({
              claimed: 0,
              completed: 0,
              deferred: 0,
              waitingForStorage: 0,
              failures: [],
            });
          },
        },
      ),
    Error,
    "intake failed",
  );
  assert(!processCalled);
});

Deno.test("safe-delete rejects deletion while sign-out purchase continuity is pending", async () => {
  let processCalled = false;
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () =>
        Promise.reject(
          new AccountDeletionIntakeError(
            "purchase_continuity_pending",
            409,
            "Finish signing out before deleting this account.",
          ),
        ),
      process: () => {
        processCalled = true;
        return Promise.resolve({
          claimed: 0,
          completed: 0,
          deferred: 0,
          waitingForStorage: 0,
          failures: [],
        });
      },
    },
  );

  assertEquals(response.status, 409);
  assertEquals(await response.json(), {
    code: "purchase_continuity_pending",
    error: "Finish signing out before deleting this account.",
  });
  assertEquals(processCalled, false);
});

Deno.test("safe-delete protocol v2 preparation is non-destructive", async () => {
  let requestCalled = false;
  let processCalled = false;
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      prepareV2: (_userId, _client, recoveryHash, acknowledgementHash) => {
        assertEquals(recoveryHash, "recovery-hash");
        assertEquals(acknowledgementHash, "acknowledgement-hash");
        return Promise.resolve({
          prepared: true,
          recoveryExpiresAt: "2099-01-01T00:00:00Z",
        });
      },
      request: () => {
        requestCalled = true;
        return Promise.reject(new Error("unexpected request"));
      },
      process: () => {
        processCalled = true;
        return Promise.resolve({
          claimed: 0,
          completed: 0,
          deferred: 0,
          waitingForStorage: 0,
          failures: [],
        });
      },
    },
    "recovery-hash",
    {
      protocolVersion: 2,
      operation: "prepare",
      acknowledgementSecretHash: "acknowledgement-hash",
    },
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), preparationV2SuccessFixture);
  assertEquals(requestCalled, false);
  assertEquals(processCalled, false);
});

Deno.test("safe-delete protocol v2 commit uses only the prepared recovery proof", async () => {
  let observedRecoveryHash: string | null = null;
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      requestV2: (_userId, _client, recoveryHash) => {
        observedRecoveryHash = recoveryHash;
        return Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
          manualProviderRevocationRequired: false,
          recoveryExpiresAt: "2027-02-09T00:00:00.000Z",
        });
      },
      process: () =>
        Promise.resolve({
          claimed: 0,
          completed: 0,
          deferred: 1,
          waitingForStorage: 0,
          failures: [],
        }),
    },
    "recovery-hash",
    { protocolVersion: 2, operation: "commit" },
  );

  assertEquals(observedRecoveryHash, "recovery-hash");
  assertEquals(response.status, 202);
  const body = await response.json();
  assertEquals(body.protocol_version, 2);
  assertEquals(body.status, "pending");
});

Deno.test("storage_pending cleanup never removes the Auth identity", async () => {
  let authCalled = false;
  let finishCalled = false;
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.resolve("storage_pending"),
      deleteAuth: () => {
        authCalled = true;
        return Promise.resolve({ succeeded: true });
      },
      finish: () => {
        finishCalled = true;
        return Promise.resolve();
      },
    },
  );

  assertEquals(authCalled, false);
  assertEquals(finishCalled, false);
  assertEquals(result.waitingForStorage, 1);
  assertEquals(result.completed, 0);
  assertEquals(result.failures, []);
});

Deno.test("Apple provider revocation is durable and completes before Auth deletion", async () => {
  const order: string[] = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => {
        order.push("cleanup");
        return Promise.resolve("provider_revocation_pending");
      },
      getProviderToken: () => {
        order.push("load_vault_token");
        return Promise.resolve({ refreshToken: "refresh-token" });
      },
      revokeProvider: (token) => {
        order.push(`revoke:${token}`);
        return Promise.resolve({ succeeded: true });
      },
      completeProvider: () => {
        order.push("persist_provider_completion");
        return Promise.resolve();
      },
      deleteAuth: () => {
        order.push("delete_auth");
        return Promise.resolve({ succeeded: true });
      },
      finish: (_client, _claim, authDeleted) => {
        order.push(authDeleted ? "complete" : "defer");
        return Promise.resolve();
      },
    },
  );

  assertEquals(order, [
    "cleanup",
    "load_vault_token",
    "revoke:refresh-token",
    "persist_provider_completion",
    "delete_auth",
    "complete",
  ]);
  assertEquals(result.completed, 1);
});

Deno.test("Apple revocation failure defers without deleting Auth or destroying the Vault token", async () => {
  let authCalled = false;
  let providerCompleted = false;
  const finishes: Array<[boolean, string | null]> = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.resolve("provider_revocation_pending"),
      getProviderToken: () =>
        Promise.resolve({ refreshToken: "refresh-token" }),
      revokeProvider: () =>
        Promise.resolve({
          succeeded: false,
          errorCode: "apple_revoke_invalid_client",
        }),
      completeProvider: () => {
        providerCompleted = true;
        return Promise.resolve();
      },
      deleteAuth: () => {
        authCalled = true;
        return Promise.resolve({ succeeded: true });
      },
      finish: (_client, _claim, authDeleted, errorCode) => {
        finishes.push([authDeleted, errorCode]);
        return Promise.resolve();
      },
    },
  );

  assertEquals(authCalled, false);
  assertEquals(providerCompleted, false);
  assertEquals(finishes, [[false, "apple_revoke_invalid_client"]]);
  assertEquals(result.failures[0]?.stage, "provider");
});

Deno.test("legacy Apple deletion returns a durable manual-revocation disposition", async () => {
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () =>
        Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
          manualProviderRevocationRequired: true,
        }),
      process: () =>
        Promise.resolve({
          claimed: 1,
          completed: 0,
          deferred: 0,
          waitingForStorage: 1,
          failures: [],
        }),
    },
  );

  assertEquals(response.status, 202);
  assertEquals(
    (await response.json()).manual_provider_revocation_required,
    true,
  );
});
