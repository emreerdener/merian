import type { SupabaseClient } from "@supabase/supabase-js";
import { assert, assertEquals, assertRejects } from "@std/assert";
import type { AccountDeletionClaim } from "../safe-delete/db.ts";
import { handleSafeDelete } from "../safe-delete/handler.ts";
import { processAccountDeletionJobs } from "../safe-delete/worker.ts";

const supabaseAdmin = {} as SupabaseClient;

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
          waitingForManualDelivery: 0,
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
          waitingForManualDelivery: 0,
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
              waitingForManualDelivery: 0,
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

Deno.test("legacy Apple dispatch acceptance waits for authoritative delivery", async () => {
  const order: string[] = [];
  let authCalled = false;
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => {
        order.push("cleanup");
        return Promise.resolve("manual_revocation_delivery_pending");
      },
      prepareManualRevocationDelivery: () => {
        order.push("prepare_attempt");
        return Promise.resolve({
          email: "apple-relay@example.invalid",
          attemptId: "00000000-0000-4000-8000-00000000d401",
          idempotencyKey:
            "account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
        });
      },
      sendManualRevocationEmail: (email, attemptId, idempotencyKey) => {
        order.push(`send:${email}:${attemptId}:${idempotencyKey}`);
        return Promise.resolve({
          succeeded: true,
          providerDeliveryId: "resend-message-1",
        });
      },
      recordManualRevocationAcceptance: (
        _client,
        _claim,
        attemptId,
        providerId,
      ) => {
        order.push(`accept:${attemptId}:${providerId}`);
        return Promise.resolve("delivery_pending");
      },
      deleteAuth: () => {
        authCalled = true;
        return Promise.resolve({ succeeded: true });
      },
    },
  );

  assertEquals(order, [
    "cleanup",
    "prepare_attempt",
    "send:apple-relay@example.invalid:00000000-0000-4000-8000-00000000d401:account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
    "accept:00000000-0000-4000-8000-00000000d401:resend-message-1",
  ]);
  assertEquals(authCalled, false);
  assertEquals(result.completed, 0);
  assertEquals(result.deferred, 0);
  assertEquals(result.waitingForManualDelivery, 1);
});

Deno.test("reclaimed jobs awaiting a delivery event do no external work", async () => {
  let prepareCalled = false;
  let authCalled = false;
  let finishCalled = false;
  const result = await processAccountDeletionJobs(supabaseAdmin, {}, {
    claim: () => Promise.resolve([pendingClaim()]),
    cleanup: () => Promise.resolve("manual_revocation_delivery_waiting"),
    prepareManualRevocationDelivery: () => {
      prepareCalled = true;
      throw new Error("must not prepare");
    },
    deleteAuth: () => {
      authCalled = true;
      return Promise.resolve({ succeeded: true });
    },
    finish: () => {
      finishCalled = true;
      return Promise.resolve();
    },
  });

  assertEquals(prepareCalled, false);
  assertEquals(authCalled, false);
  assertEquals(finishCalled, false);
  assertEquals(result.waitingForManualDelivery, 1);
  assertEquals(result.deferred, 0);
});

Deno.test("a matching delivery event journaled before acceptance can unlock Auth", async () => {
  const order: string[] = [];
  const result = await processAccountDeletionJobs(supabaseAdmin, {}, {
    claim: () => Promise.resolve([pendingClaim()]),
    cleanup: () => Promise.resolve("manual_revocation_delivery_pending"),
    prepareManualRevocationDelivery: () =>
      Promise.resolve({
        email: "apple-relay@example.invalid",
        attemptId: "00000000-0000-4000-8000-00000000d401",
        idempotencyKey:
          "account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
      }),
    sendManualRevocationEmail: () =>
      Promise.resolve({
        succeeded: true,
        providerDeliveryId: "resend-message-1",
      }),
    recordManualRevocationAcceptance: () => {
      order.push("commit_matching_delivery");
      return Promise.resolve("delivered");
    },
    deleteAuth: () => {
      order.push("delete_auth");
      return Promise.resolve({ succeeded: true });
    },
    finish: (_client, _claim, authDeleted) => {
      order.push(authDeleted ? "complete" : "defer");
      return Promise.resolve();
    },
  });

  assertEquals(order, ["commit_matching_delivery", "delete_auth", "complete"]);
  assertEquals(result.completed, 1);
});

Deno.test("a terminal delivery event schedules retry without deleting Auth", async () => {
  let authCalled = false;
  let finishCalled = false;
  const result = await processAccountDeletionJobs(supabaseAdmin, {}, {
    claim: () => Promise.resolve([pendingClaim()]),
    cleanup: () => Promise.resolve("manual_revocation_delivery_pending"),
    prepareManualRevocationDelivery: () =>
      Promise.resolve({
        email: "apple-relay@example.invalid",
        attemptId: "00000000-0000-4000-8000-00000000d401",
        idempotencyKey:
          "account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
      }),
    sendManualRevocationEmail: () =>
      Promise.resolve({
        succeeded: true,
        providerDeliveryId: "resend-message-1",
      }),
    recordManualRevocationAcceptance: () => Promise.resolve("retry_required"),
    deleteAuth: () => {
      authCalled = true;
      return Promise.resolve({ succeeded: true });
    },
    finish: () => {
      finishCalled = true;
      return Promise.resolve();
    },
  });

  assertEquals(authCalled, false);
  assertEquals(finishCalled, false);
  assertEquals(result.deferred, 1);
  assertEquals(result.failures, [{
    jobId: pendingClaim().jobId,
    stage: "manual_delivery",
    code: "manual_revocation_delivery_retry_required",
  }]);
});

Deno.test("legacy Apple delivery failure retains Auth and retries the same job", async () => {
  let authCalled = false;
  let deliveryCompleted = false;
  const finishes: Array<[boolean, string | null]> = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.resolve("manual_revocation_delivery_pending"),
      prepareManualRevocationDelivery: () =>
        Promise.resolve({
          email: "apple-relay@example.invalid",
          attemptId: "00000000-0000-4000-8000-00000000d401",
          idempotencyKey:
            "account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
        }),
      sendManualRevocationEmail: () =>
        Promise.resolve({
          succeeded: false,
          errorCode: "manual_revocation_email_http_503",
        }),
      recordManualRevocationAcceptance: () => {
        deliveryCompleted = true;
        return Promise.resolve("delivery_pending");
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
  assertEquals(deliveryCompleted, false);
  assertEquals(finishes, [[false, "manual_revocation_email_http_503"]]);
  assertEquals(result.failures[0]?.stage, "manual_delivery");
});

Deno.test("ambiguous manual delivery completion never reaches Auth deletion", async () => {
  let authCalled = false;
  const finishes: Array<[boolean, string | null]> = [];
  const result = await processAccountDeletionJobs(
    supabaseAdmin,
    {},
    {
      claim: () => Promise.resolve([pendingClaim()]),
      cleanup: () => Promise.resolve("manual_revocation_delivery_pending"),
      prepareManualRevocationDelivery: () =>
        Promise.resolve({
          email: "apple-relay@example.invalid",
          attemptId: "00000000-0000-4000-8000-00000000d401",
          idempotencyKey:
            "account-deletion-manual-apple/00000000-0000-4000-8000-00000000d401",
        }),
      sendManualRevocationEmail: () =>
        Promise.resolve({
          succeeded: true,
          providerDeliveryId: "resend-message-1",
        }),
      recordManualRevocationAcceptance: () =>
        Promise.reject(new Error("database response lost")),
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
  assertEquals(finishes, [[false, "manual_revocation_delivery_failed"]]);
  assertEquals(result.failures[0], {
    jobId: pendingClaim().jobId,
    stage: "manual_delivery",
    code: "manual_revocation_delivery_failed",
  });
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
          waitingForManualDelivery: 0,
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
