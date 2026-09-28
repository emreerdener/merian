import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const commit = "SELECT * FROM pg_temp.commit_invocation($1,$2,$3,1)";
const complete =
  "SELECT public.complete_identification_invocation($1,$2,$3,'draft','{\"input_tokens\":100,\"candidate_tokens\":40}')";
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );

async function waitForBlock(observer: Client, waiter: number, blocker: number) {
  for (let i = 0; i < 100; i++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int = ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected accounting lock was not observed");
}

for (
  const scenario of [
    "duplicate commitment",
    "completion before deletion",
    "deletion before completion",
  ]
) {
  Deno.test({
    name: `Identification invocation DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Accounting race fixtures require a disposable loopback database",
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      let owner: string | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/identification_invocation_accounting.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN ACCOUNTING SYNTHETIC HELPERS\n",
        )[1]?.split("-- END ACCOUNTING SYNTHETIC HELPERS")[0];
        assert(helpers);
        for (const client of clients) await client.queryArray(helpers);
        const fixture = (await observer.queryObject<
          { reservation: string; owner_id: string; token: string }
        >("SELECT * FROM pg_temp.seed_invocation()")).rows[0];
        owner = fixture.owner_id;
        const args = [fixture.reservation, owner, fixture.token];
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        if (scenario === "duplicate commitment") {
          const admitted = (await first.queryObject<
            { invocation_id: string; may_dispatch: boolean }
          >(commit, args)).rows[0];
          assert(admitted.may_dispatch);
          const duplicate = settle(
            second.queryObject<
              { invocation_id: string; may_dispatch: boolean }
            >(commit, args),
          );
          await waitForBlock(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await duplicate;
          assert(result.ok);
          assertEquals(result.value.rows, [{
            invocation_id: admitted.invocation_id,
            may_dispatch: false,
          }]);
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.identification_invocations WHERE reservation_id=$1",
              [fixture.reservation],
            )).rows[0].count,
            1,
          );
        } else {
          const invocation =
            (await observer.queryObject<{ invocation_id: string }>(
              commit,
              args,
            )).rows[0].invocation_id;
          const completeArgs = [invocation, owner, fixture.token];
          const deleteSql = "DELETE FROM public.users WHERE id=$1";
          if (scenario === "completion before deletion") {
            await first.queryArray(complete, completeArgs);
            const deletion = settle(second.queryArray(deleteSql, [owner]));
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await deletion).ok);
            await second.queryArray("COMMIT");
          } else {
            await first.queryArray(deleteSql, [owner]);
            const completion = settle(
              second.queryArray(complete, completeArgs),
            );
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assertEquals((await completion).ok, false);
            await second.queryArray("ROLLBACK");
          }
          const records = await observer.queryObject<
            {
              user_id: string | null;
              scan_id: string | null;
              source_id: string | null;
              outcome: string;
            }
          >(
            "SELECT e.user_id,e.scan_id,e.source_id,e.outcome FROM public.ai_usage_events e JOIN internal.identification_invocations i ON i.event_id=e.id WHERE i.id=$1",
            [invocation],
          );
          assertEquals(records.rows, [{
            user_id: null,
            scan_id: null,
            source_id: null,
            outcome: scenario === "completion before deletion"
              ? "success"
              : "unknown",
          }]);
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (owner) {
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            owner,
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]);
        }
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
