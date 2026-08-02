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
  assertEquals((await response.json()).status, "completed");
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

Deno.test("safe-delete remains accepted if fast-path claiming fails", async () => {
  const response = await handleSafeDelete(
    pendingClaim().userId,
    supabaseAdmin,
    {
      request: () =>
        Promise.resolve({
          jobId: pendingClaim().jobId,
          status: "pending",
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
