import { assertEquals, assertRejects } from "@std/assert";
import { requireReportableUser, upsertUserReport } from "./db.ts";

function rpcClient(rows: unknown[]) {
  return {
    rpc: () => Promise.resolve({ data: rows, error: null }),
  };
}

Deno.test("requireReportableUser rejects self reports before database access", async () => {
  await assertRejects(
    () => requireReportableUser("same", "same", rpcClient([]) as never),
    Error,
    "own profile",
  );
});

Deno.test("requireReportableUser rejects profiles outside the visible profile contract", async () => {
  await assertRejects(
    () => requireReportableUser("viewer", "target", rpcClient([]) as never),
    Error,
    "not found",
  );
});

Deno.test("upsertUserReport preserves terminal state by omitting status", async () => {
  let payload: Record<string, unknown> | undefined;
  let conflict = "";
  const client = {
    from: () => ({
      upsert: (
        row: Record<string, unknown>,
        options: { onConflict: string },
      ) => {
        payload = row;
        conflict = options.onConflict;
        return Promise.resolve({ error: null });
      },
    }),
  };

  await upsertUserReport({
    reporterUserId: "reporter",
    reportedUserId: "reported",
    reason: "Spam",
    details: null,
  }, client as never);

  assertEquals(conflict, "reporter_user_id,reported_user_id");
  assertEquals(payload?.status, undefined);
});
