import { assertEquals, assertRejects } from "@std/assert";
import {
  downgradeExpiredSubscriptionPass,
  fetchExpiredSubscriptionPassUsers,
} from "./db.ts";

type Call = { method: string; args: unknown[] };

function fetchClient(
  result: { data?: unknown[] | null; error?: { message: string } | null },
  calls: Call[] = [],
) {
  const query = {
    select: (...args: unknown[]) => {
      calls.push({ method: "select", args });
      return query;
    },
    eq: (...args: unknown[]) => {
      calls.push({ method: "eq", args });
      return query;
    },
    not: (...args: unknown[]) => {
      calls.push({ method: "not", args });
      return query;
    },
    lte: (...args: unknown[]) => {
      calls.push({ method: "lte", args });
      return query;
    },
    order: (...args: unknown[]) => {
      calls.push({ method: "order", args });
      return query;
    },
    limit: (...args: unknown[]) => {
      calls.push({ method: "limit", args });
      return Promise.resolve(result);
    },
  };

  return {
    calls,
    client: {
      from: (...args: unknown[]) => {
        calls.push({ method: "from", args });
        return query;
      },
    },
  };
}

function updateClient(
  result: { data?: boolean | null; error?: { message: string } | null },
  calls: Call[] = [],
) {
  return {
    calls,
    client: {
      rpc: (...args: unknown[]) => {
        calls.push({ method: "rpc", args });
        return Promise.resolve(result);
      },
    },
  };
}

Deno.test("fetchExpiredSubscriptionPassUsers: queries only expired timed pro users", async () => {
  const boundaryIso = "2026-06-16T12:00:00.000Z";
  const { client, calls } = fetchClient({
    data: [{ id: "expired-a" }, { id: "expired-b" }],
    error: null,
  });

  const users = await fetchExpiredSubscriptionPassUsers(
    boundaryIso,
    client as never,
    25,
  );

  assertEquals(users, [{ id: "expired-a" }, { id: "expired-b" }]);
  assertEquals(calls, [
    { method: "from", args: ["users"] },
    { method: "select", args: ["id"] },
    { method: "eq", args: ["subscription_tier", "pro"] },
    { method: "not", args: ["subscription_expires_at", "is", null] },
    { method: "lte", args: ["subscription_expires_at", boundaryIso] },
    {
      method: "order",
      args: ["subscription_expires_at", { ascending: true }],
    },
    { method: "limit", args: [25] },
  ]);
});

Deno.test("fetchExpiredSubscriptionPassUsers: surfaces database errors", async () => {
  const { client } = fetchClient({
    data: null,
    error: { message: "database unavailable" },
  });

  await assertRejects(
    () =>
      fetchExpiredSubscriptionPassUsers(
        "2026-06-16T12:00:00.000Z",
        client as never,
      ),
    Error,
    "Failed to fetch expired subscription passes: database unavailable",
  );
});

Deno.test("downgradeExpiredSubscriptionPass: downgrades only if the row is still expired timed pro", async () => {
  const boundaryIso = "2026-06-16T12:00:00.000Z";
  const { client, calls } = updateClient({
    data: true,
    error: null,
  });

  const didDowngrade = await downgradeExpiredSubscriptionPass(
    "expired-user",
    boundaryIso,
    client as never,
  );

  assertEquals(didDowngrade, true);
  assertEquals(calls, [
    {
      method: "rpc",
      args: ["refresh_expired_entitlement_projection", {
        p_user_id: "expired-user",
        p_boundary: boundaryIso,
      }],
    },
  ]);
});

Deno.test("downgradeExpiredSubscriptionPass: returns false when the guarded update matches no rows", async () => {
  const { client } = updateClient({ data: false, error: null });

  assertEquals(
    await downgradeExpiredSubscriptionPass(
      "renewed-user",
      "2026-06-16T12:00:00.000Z",
      client as never,
    ),
    false,
  );
});

Deno.test("downgradeExpiredSubscriptionPass: surfaces database errors", async () => {
  const { client } = updateClient({
    data: null,
    error: { message: "permission denied" },
  });

  await assertRejects(
    () =>
      downgradeExpiredSubscriptionPass(
        "expired-user",
        "2026-06-16T12:00:00.000Z",
        client as never,
      ),
    Error,
    "Failed to downgrade expired subscription pass: permission denied",
  );
});
