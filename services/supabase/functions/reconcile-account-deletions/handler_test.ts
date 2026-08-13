import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import { handleReconcileAccountDeletions } from "./handler.ts";

const SERVER_KEY = ["sb", "secret", "fixture", "account", "deletion", "reaper"]
  .join("_");
const admin = {} as SupabaseClient;

function request(body: unknown, key = SERVER_KEY): Request {
  return new Request("https://example.test/reconcile-account-deletions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: key,
    },
    body: JSON.stringify(body),
  });
}

Deno.test("authenticated dry-run proves the handler without creating or mutating work", async () => {
  let clientCreations = 0;
  let workerCalls = 0;
  const response = await handleReconcileAccountDeletions(
    request({ dry_run: true }),
    {
      authorize: () => ({ ok: true, serverApiKey: SERVER_KEY }),
      createClient: () => {
        clientCreations += 1;
        return admin;
      },
      processAccounts: () => {
        workerCalls += 1;
        throw new Error("dry-run must not claim account jobs");
      },
      processStorage: () => {
        workerCalls += 1;
        throw new Error("dry-run must not claim storage jobs");
      },
      prunePreparations: () => {
        workerCalls += 1;
        throw new Error("dry-run must not prune preparations");
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  assertEquals(await response.json(), { success: true, dry_run: true });
  assertEquals(clientCreations, 0);
  assertEquals(workerCalls, 0);
});

Deno.test("dry-run authenticates before parsing and rejects malformed modes", async () => {
  let clientCreations = 0;
  const denied = await handleReconcileAccountDeletions(
    request({ dry_run: true }, "wrong"),
    {
      authorize: () => ({ ok: false, reason: "token_mismatch" }),
      createClient: () => {
        clientCreations += 1;
        return admin;
      },
    },
  );
  assertEquals(denied.status, 401);

  for (
    const body of [
      { dry_run: false },
      { dry_run: "true" },
      { dry_run: true, limit: 1 },
    ]
  ) {
    const response = await handleReconcileAccountDeletions(request(body), {
      authorize: () => ({ ok: true, serverApiKey: SERVER_KEY }),
      createClient: () => {
        clientCreations += 1;
        return admin;
      },
    });
    assertEquals(response.status, 400);
  }
  assertEquals(clientCreations, 0);
});

Deno.test("ordinary reaper requests retain bounded worker semantics", async () => {
  const calls: string[] = [];
  const response = await handleReconcileAccountDeletions(
    request({ limit: 3 }),
    {
      authorize: () => ({ ok: true, serverApiKey: SERVER_KEY }),
      createClient: () => admin,
      processAccounts: (_client, options) => {
        calls.push(`account:${options?.limit}`);
        return Promise.resolve({
          claimed: 1,
          completed: 0,
          deferred: 1,
          waitingForStorage: 0,
          failures: [],
        });
      },
      processStorage: (_client, limit) => {
        calls.push(`storage:${limit}`);
        return Promise.resolve({
          claimed: 1,
          completed: 0,
          advanced: 0,
          deferred: 1,
          failures: [],
        });
      },
      prunePreparations: (_client, limit) => {
        calls.push(`prune:${limit}`);
        return Promise.resolve(2);
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(calls, ["account:3", "storage:3", "prune:3"]);
  assertEquals((await response.json()).recovery_preparations_pruned, 2);
});
