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
    "binding before intent",
    "intent before binding",
    "repeatable read intent",
  ]
) {
  Deno.test({
    name: `Source intent DB concurrency - ${scenario}`,
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
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, observation, source],
        );
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          otherOwner,
          otherObservation,
        ]);
        const insertIntent = (client: Client) =>
          client.queryArray(
            `INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot)
          VALUES($3,$2,$1,(pg_temp.history_append_request($2,$3)-'result_snapshot') || jsonb_build_object('entitlement_protocol',3,'identification_protocol',6,'history_protocol',7,'expected_processor_permission','google_gemini'))`,
            [otherOwner, otherObservation, child],
          );
        const insertBinding = (client: Client) =>
          client.queryArray("SELECT pg_temp.store_source($1,$2,$3,$4)", [
            owner,
            observation,
            source,
            child,
          ]);
        if (scenario === "repeatable read intent") {
          await first.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
          let code: string | undefined;
          try {
            await insertIntent(first);
          } catch (error) {
            code = (error as { fields?: { code?: string } }).fields?.code;
          }
          assertEquals(code, "25000");
          await first.queryArray("ROLLBACK");
          return;
        }
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
        const bindingFirst = scenario === "binding before intent";
        await (bindingFirst ? insertBinding(first) : insertIntent(first));
        let code: string | undefined;
        pending = (bindingFirst ? insertIntent(second) : insertBinding(second))
          .then(() => true, (error: { fields?: { code?: string } }) => {
            code = error.fields?.code;
            return false;
          });
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        assertEquals(await pending, false);
        assertEquals(code, "22023");
        await second.queryArray("ROLLBACK");
        const counts =
          (await observer.queryObject<{ bindings: string; intents: string }>(
            "SELECT (SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1)::text AS bindings,(SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1)::text AS intents",
            [child],
          )).rows[0];
        assertEquals(
          counts,
          bindingFirst
            ? { bindings: "1", intents: "0" }
            : { bindings: "0", intents: "1" },
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
