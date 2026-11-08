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
    if (
      (await observer.queryObject<{ blocked: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
        [blocker, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected execution status lock not observed");
}
for (
  const scenario of [
    "read first",
    "dispatch first",
    "deletion first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Execution status DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
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
          "UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,reader_enabled=TRUE,execution_status_api_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3),repeat('a',64))",
          args,
        );
        const provenance = (await observer.queryObject<{ value: unknown }>(
          "SELECT pg_temp.funded_provenance($1) AS value",
          [analysis],
        )).rows[0].value;
        const request = JSON.stringify({
          schema_version: 1,
          observation_id: observation,
          analysis_id: analysis,
          source_analysis_id: null,
          request_digest: "a".repeat(64),
        });
        for (const client of clients) {
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,FALSE)",
            [JSON.stringify({ sub: owner, role: "authenticated" })],
          );
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
        const read = (client: Client) =>
          client.queryObject<{ value: { state: string } }>(
            "SELECT public.get_owned_observation_analysis_execution($1::jsonb,9) AS value",
            [request],
          );
        const dispatch = (client: Client) =>
          client.queryObject<{ value: { may_dispatch: boolean } }>(
            "SELECT internal.dispatch_observation_analysis($1,$2,$3,(quota->>'lease_token')::uuid,$4::jsonb) AS value FROM internal.observation_analysis_intents WHERE analysis_id=$3",
            [...args, JSON.stringify(provenance)],
          );
        if (scenario === "read first") {
          assertEquals((await read(first)).rows[0].value.state, "admitted");
          const pending = settle(dispatch(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          assertEquals(result.value.rows[0].value.may_dispatch, true);
          await second.queryArray("COMMIT");
          assertEquals(
            (await read(observer)).rows[0].value.state,
            "dispatched",
          );
        } else {
          if (scenario === "dispatch first") await dispatch(first);
          else if (scenario === "account deletion first") {
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
          const pending = settle(read(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "dispatch first") {
            assert(result.ok);
            assertEquals(result.value.rows[0].value.state, "dispatched");
            await second.queryArray("COMMIT");
          } else {
            assertEquals(result.ok, false);
            await second.queryArray("ROLLBACK");
          }
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET admission_enabled=$1,dispatch_enabled=$2,reader_enabled=$3,execution_status_api_enabled=$4,enrollment_enabled=$5",
            [
              previous.admission_enabled,
              previous.dispatch_enabled,
              previous.reader_enabled,
              previous.execution_status_api_enabled,
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
