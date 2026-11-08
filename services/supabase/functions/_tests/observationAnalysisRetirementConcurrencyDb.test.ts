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
  throw new Error("Expected retirement lock not observed");
}
for (
  const scenario of [
    "retire first",
    "dispatch first",
    "duplicate retirement",
    "deletion first",
    "retire before deletion",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Retirement DB concurrency - ${scenario}`,
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
        analysis = crypto.randomUUID(),
        operation = crypto.randomUUID();
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
          "UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,orchestration_enabled=TRUE,execution_retirement_api_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3),repeat('a',64))",
          args,
        );
        const provenance = (await observer.queryObject<{ value: unknown }>(
          "SELECT pg_temp.funded_provenance($1) AS value",
          [analysis],
        )).rows[0].value;
        const work =
          (await observer.queryObject<{ value: { work_token: string } }>(
            "SELECT internal.claim_observation_analysis($1,$2,$3) AS value",
            args,
          )).rows[0].value.work_token;
        const request = JSON.stringify({
          schema_version: 1,
          operation_id: operation,
          observation_id: observation,
          analysis_id: analysis,
          source_analysis_id: null,
          request_digest: "a".repeat(64),
        });
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
        const retire = (client: Client) =>
          client.queryObject<{ value: unknown }>(
            "SELECT public.retire_owned_observation_analysis_execution($1,$2::jsonb,9) AS value",
            [owner, request],
          );
        const dispatch = (client: Client) =>
          client.queryObject<{ value: { may_dispatch: boolean } }>(
            "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'dispatch',$5::jsonb) AS value",
            [...args, work, JSON.stringify({ provenance })],
          );
        const deletion = async (client: Client) => {
          await client.queryArray(
            "SELECT internal.lock_owned_observation_evidence($1,$2)",
            [owner, observation],
          );
          await client.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        };
        if (
          scenario === "retire first" || scenario === "duplicate retirement" ||
          scenario === "retire before deletion"
        ) {
          const before = (await retire(first)).rows[0].value;
          const pending = scenario === "retire first"
            ? settle(dispatch(second))
            : scenario === "duplicate retirement"
            ? settle(retire(second))
            : settle(deletion(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "retire first") {
            assertEquals(result.ok, false);
            await second.queryArray("ROLLBACK");
          } else {
            assert(result.ok);
            if (scenario === "duplicate retirement") {
              assert(result.value && "rows" in result.value);
              assertEquals(result.value.rows[0].value, before);
            }
            await second.queryArray("COMMIT");
          }
        } else {
          if (scenario === "dispatch first") {
            assertEquals(
              (await dispatch(first)).rows[0].value.may_dispatch,
              true,
            );
          } else if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else await deletion(first);
          const pending = settle(retire(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await pending).ok, false);
          await second.queryArray("ROLLBACK");
        }
        const rows = (await observer.queryObject<
          { receipts: number; invocations: number; state: string | null }
        >(
          "SELECT (SELECT count(*)::int FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=$1) AS receipts,(SELECT count(*)::int FROM internal.identification_invocations WHERE scan_id=$1) AS invocations,(SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id=$1) AS state",
          [analysis],
        )).rows[0];
        if (
          scenario === "retire first" || scenario === "duplicate retirement"
        ) {
          assertEquals(rows, {
            receipts: 1,
            invocations: 0,
            state: "refunded",
          });
        } else if (scenario === "dispatch first") {
          assertEquals(rows, {
            receipts: 0,
            invocations: 1,
            state: "committed",
          });
        } else assertEquals(rows.receipts, 0);
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET admission_enabled=$1,dispatch_enabled=$2,append_enabled=$3,orchestration_enabled=$4,execution_retirement_api_enabled=$5,enrollment_enabled=$6",
            [
              previous.admission_enabled,
              previous.dispatch_enabled,
              previous.append_enabled,
              previous.orchestration_enabled,
              previous.execution_retirement_api_enabled,
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
