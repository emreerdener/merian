import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const appendSQL =
  "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3)) AS snapshot";
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function waitForBlock(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int = ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected observation append lock was not observed");
}

for (
  const scenario of [
    "duplicate",
    "two first results",
    "deletion first",
    "append first",
  ]
) {
  Deno.test({
    name: `Observation analysis append DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Requires a disposable loopback database",
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        analysis = crypto.randomUUID();
      let oldGate = false;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_append.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN HISTORY APPEND SYNTHETIC HELPERS\n",
        )[1]?.split("-- END HISTORY APPEND SYNTHETIC HELPERS")[0];
        assert(helpers);
        for (const client of clients) await client.queryArray(helpers);
        oldGate = (await observer.queryObject<{ enabled: boolean }>(
          "SELECT append_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0].enabled;
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=TRUE",
        );
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
        const args = [owner, observation, analysis];
        // Model the established owner-first deletion fence, without invoking a
        // legacy deletion RPC that intentionally refuses enrolled observations.
        const fence = async (client: Client) => {
          await client.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await client.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || $1::text,0::bigint))",
            [observation],
          );
          await client.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        };
        if (scenario === "deletion first") {
          await fence(first);
          const result = settle(second.queryObject(appendSQL, args));
          await waitForBlock(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await result).ok, false);
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_analysis_results WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
        } else {
          const saved =
            (await first.queryObject<{ snapshot: string }>(appendSQL, args))
              .rows[0].snapshot;
          if (scenario === "append first") {
            const deletion = settle(fence(second));
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await deletion).ok);
            await second.queryArray("COMMIT");
            assertEquals(
              (await settle(observer.queryObject(appendSQL, args))).ok,
              false,
            );
          } else {
            const next = scenario === "duplicate"
              ? analysis
              : crypto.randomUUID();
            const pending = settle(
              second.queryObject<{ snapshot: string }>(appendSQL, [
                owner,
                observation,
                next,
              ]),
            );
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const result = await pending;
            assert(result.ok);
            await second.queryArray("COMMIT");
            if (scenario === "duplicate") {
              assertEquals(result.value.rows[0].snapshot, saved);
            } else {assertEquals(
                JSON.parse(result.value.rows[0].snapshot).ordinal,
                2,
              );}
            const state = (await observer.queryObject<
              {
                selected: string;
                revision: number;
                results: number;
                receipts: number;
              }
            >(
              "SELECT selected_analysis_id AS selected,state_revision AS revision,(SELECT count(*)::int FROM internal.observation_analysis_results WHERE observation_id=$1) AS results,(SELECT count(*)::int FROM internal.observation_history_reconciliation WHERE observation_id=$1) AS receipts FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0];
            assertEquals(state, {
              selected: analysis,
              revision: 1,
              results: scenario === "duplicate" ? 1 : 2,
              receipts: 1,
            });
          }
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=$1",
          [oldGate],
        );
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          observation,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
          [observation],
        );
        await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
          owner,
        ]);
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          owner,
        ]);
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
