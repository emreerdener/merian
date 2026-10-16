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
    "binding before evidence",
    "evidence before binding",
    "repeatable read evidence",
  ]
) {
  Deno.test({
    name: `Source evidence writer DB concurrency - ${scenario}`,
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
      let previousMedia = false;
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
        previousMedia = (await observer.queryObject<{ enabled: boolean }>(
          "SELECT media_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0].enabled;
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
        for (const client of clients) {
          await client.queryArray(
            "SELECT set_config('request.jwt.claim.role','service_role',false)",
          );
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=TRUE",
        );
        const insertEvidence = (client: Client) =>
          client.queryArray(
            `SELECT public.reserve_owned_observation_evidence_cohort($1,$2,$3,
          jsonb_build_array(jsonb_build_object('media_id',$4::text,'content_type','image/jpeg','byte_count',46,'sha256',repeat('b',64))))`,
            [otherOwner, otherObservation, child, crypto.randomUUID()],
          );
        const insertBinding = (client: Client) =>
          client.queryArray("SELECT pg_temp.store_source($1,$2,$3,$4)", [
            owner,
            observation,
            source,
            child,
          ]);
        if (scenario === "repeatable read evidence") {
          await first.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
          let code: string | undefined;
          try {
            await insertEvidence(first);
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
        const bindingFirst = scenario === "binding before evidence";
        await (bindingFirst ? insertBinding(first) : insertEvidence(first));
        let code: string | undefined;
        pending =
          (bindingFirst ? insertEvidence(second) : insertBinding(second))
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
          (await observer.queryObject<{ bindings: string; evidences: string }>(
            "SELECT (SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1)::text AS bindings,(SELECT count(*) FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=$1)::text AS evidences",
            [child],
          )).rows[0];
        assertEquals(
          counts,
          bindingFirst
            ? { bindings: "1", evidences: "0" }
            : { bindings: "0", evidences: "1" },
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await pending;
        if (previous !== undefined) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=$1,enrollment_enabled=FALSE,media_enabled=$2",
            [previous, previousMedia],
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
