import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected recovery lock not observed");
}
for (
  const scenario of [
    "duplicate claim",
    "deletion first",
    "outcome first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Observation recovery DB concurrency - ${scenario}`,
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
        analysis = crypto.randomUUID();
      const args = [owner, observation, analysis];
      let previous: Record<string, unknown> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_funding.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN FUNDED ANALYSIS HELPERS\n")[1].split(
            "-- END FUNDED ANALYSIS HELPERS",
          )[0],
        );
        previous =
          (await observer.queryObject<{ value: Record<string, unknown> }>(
            "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
          )).rows[0].value;
        await observer.queryArray("SELECT pg_temp.seed_funded_history($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET orchestration_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3),repeat('a',64))",
          args,
        );
        let payload: unknown;
        if (scenario !== "duplicate claim") {
          await observer.queryArray(
            "SELECT pg_temp.funded_dispatch($1,$2,$3)",
            args,
          );
          payload = (await observer.queryObject<{ value: unknown }>(
            "SELECT jsonb_build_object('quota_token',quota->'lease_token','value',jsonb_build_object('schema_version',1,'provenance',pg_temp.funded_provenance(analysis_id),'outcome',jsonb_build_object('kind','refusal'),'usage','{}'::jsonb)) AS value FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [analysis],
          )).rows[0].value;
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
        const deletion = async (client: Client) => {
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
        const output = (client: Client) =>
          client.queryArray(
            "SELECT public.advance_owned_observation_analysis($1,$2,$3,NULL,'outcome',$4::jsonb)",
            [...args, JSON.stringify(payload)],
          );
        if (scenario === "duplicate claim") {
          const claimed = await first.queryObject<
            { value: { claimed: boolean } }
          >(
            "SELECT internal.claim_observation_analysis($1,$2,$3) AS value",
            args,
          );
          assertEquals(claimed.rows[0].value.claimed, true);
          const pending = settle(
            second.queryObject<{ value: { claimed: boolean } }>(
              "SELECT internal.claim_observation_analysis($1,$2,$3) AS value",
              args,
            ),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          assertEquals(result.value.rows[0].value.claimed, false);
          await second.queryArray("COMMIT");
        } else if (scenario === "outcome first") {
          await output(first);
          const pending = settle(deletion(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
        } else {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else await deletion(first);
          const pending = settle(output(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await pending).ok, false);
          await second.queryArray("ROLLBACK");
        }
        if (scenario !== "duplicate claim") {
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [analysis],
            )).rows[0].count,
            0,
          );
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET orchestration_enabled=$1,admission_enabled=$2,dispatch_enabled=$3,append_enabled=$4,enrollment_enabled=$5",
            [
              previous.orchestration_enabled,
              previous.admission_enabled,
              previous.dispatch_enabled,
              previous.append_enabled,
              previous.enrollment_enabled,
            ],
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
