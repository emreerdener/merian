import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected source storage lock not observed");
}
for (
  const scenario of [
    "distinct children",
    "parent deletion first",
    "account deletion first",
    "binding before deletion",
  ]
) {
  Deno.test({
    name: `Source storage DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        source = crypto.randomUUID(),
        child = crypto.randomUUID();
      let previous: boolean | undefined;
      let pending: Promise<boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        const fixture = await Deno.readTextFile(
          new URL(
            "../../tests/observation_source_storage.sql",
            import.meta.url,
          ),
        );
        const helpers =
          fixture.split("-- BEGIN SOURCE STORAGE HELPERS\n")[1].split(
            "-- END SOURCE STORAGE HELPERS",
          )[0];
        for (const client of clients) await client.queryArray(helpers);
        previous = (await observer.queryObject<{ enabled: boolean }>(
          "SELECT append_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0].enabled;
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, observation, source],
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
        const insert = (client: Client, analysis: string) =>
          client.queryArray("SELECT pg_temp.store_source($1,$2,$3,$4)", [
            owner,
            observation,
            source,
            analysis,
          ]);
        if (
          scenario === "distinct children" ||
          scenario === "binding before deletion"
        ) {
          await insert(first, child);
        } else if (scenario === "account deletion first") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } else {
          await first.queryArray(
            "SELECT internal.lock_owned_observation_evidence($1,$2)",
            [owner, observation],
          );
          await first.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        }
        pending = (scenario === "binding before deletion"
          ? second.queryArray("SELECT public.apply_user_tombstone($1)", [owner])
          : insert(second, crypto.randomUUID())).then(() =>
            true, () =>
            false);
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        const succeeded = await pending;
        assertEquals(succeeded, scenario === "binding before deletion");
        await second.queryArray(succeeded ? "COMMIT" : "ROLLBACK");
        const counts =
          (await observer.queryObject<{ bindings: string; occupancy: string }>(
            "SELECT (SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE observation_id=$1)::text AS bindings,(SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE observation_id=$1)::text AS occupancy",
            [observation],
          )).rows[0];
        assertEquals(
          counts,
          scenario === "distinct children"
            ? { bindings: "1", occupancy: "1" }
            : { bindings: "0", occupancy: "0" },
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await pending;
        if (previous !== undefined) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=$1,enrollment_enabled=FALSE",
            [previous],
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
