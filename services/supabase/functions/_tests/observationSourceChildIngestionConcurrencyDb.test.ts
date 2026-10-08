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
    "job first",
    "binding before job",
    "intent first",
    "binding before intent",
    "repeatable read writer",
    "repeatable read binding",
    "account deletion first",
    "binding before account deletion",
  ]
) {
  Deno.test({
    name: `Source child ingestion DB concurrency - ${scenario}`,
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
      const otherOwner = crypto.randomUUID(),
        otherObservation = crypto.randomUUID();
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
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          otherOwner,
          otherObservation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, observation, source],
        );
        for (const client of [first, second]) {
          await client.queryArray(
            scenario.startsWith("repeatable read")
              ? "BEGIN ISOLATION LEVEL REPEATABLE READ"
              : "BEGIN",
          );
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
        if (scenario.includes("account deletion")) {
          const bindingFirst = scenario.startsWith("binding");
          const deletion = (client: Client) =>
            client.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          await (bindingFirst ? insert(first, child) : deletion(first));
          pending = (bindingFirst ? deletion(second) : insert(second, child))
            .then(() => true, () => false);
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals(await pending, bindingFirst);
          await second.queryArray(bindingFirst ? "COMMIT" : "ROLLBACK");
          const count = (await observer.queryObject<{ count: string }>(
            "SELECT count(*)::text AS count FROM internal.observation_analysis_source_bindings WHERE observation_id=$1",
            [observation],
          )).rows[0].count;
          assertEquals(count, "0");
          return;
        }
        if (scenario.startsWith("repeatable read")) {
          const query = scenario.endsWith("binding")
            ? insert(second, child)
            : second.queryArray(
              "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES($1,$2)",
              [child, otherOwner],
            );
          await query.then(() => {
            throw new Error("Frozen snapshot unexpectedly accepted");
          }, (error) => {
            assertEquals(error.fields?.code, "25000");
            assertEquals(
              error.message,
              "analysis_history_current_snapshot_required",
            );
          });
          return;
        }
        const table = scenario.includes("intent")
          ? "scan_ingestion_intents"
          : "scan_ingestion_jobs";
        const legacy = (client: Client) =>
          client.queryArray(
            `INSERT INTO public.${table}(scan_id,user_id) VALUES($1,$2)`,
            ["{" + child.toUpperCase().replaceAll("-", "") + "}", otherOwner],
          );
        const bindingFirst = scenario.startsWith("binding");
        await (bindingFirst ? insert(first, child) : legacy(first));
        pending = (bindingFirst ? legacy(second) : insert(second, child)).then(
          () => true,
          (error) => {
            assertEquals(error.fields?.code, "22023");
            assertEquals(error.message, "analysis_history_operation_conflict");
            return false;
          },
        );
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        assertEquals(await pending, false);
        await second.queryArray("ROLLBACK");
        const counts =
          (await observer.queryObject<{ bindings: string; legacy: string }>(
            `SELECT (SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1)::text AS bindings,
          (SELECT count(*) FROM public.${table} WHERE internal.source_child_uuid(scan_id)=$1)::text AS legacy`,
            [child],
          )).rows[0];
        assertEquals(
          counts,
          bindingFirst
            ? { bindings: "1", legacy: "0" }
            : { bindings: "0", legacy: "1" },
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
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          otherOwner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          otherOwner,
        ]).catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
