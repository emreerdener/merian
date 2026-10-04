import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const completeSQL =
  "SELECT internal.complete_observation_analysis($1,$2,$3) AS receipt";
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
  throw new Error("Expected funding lock was not observed");
}

for (
  const scenario of [
    "duplicate completion",
    "deletion first",
    "completion first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Protected photo DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Requires disposable loopback DB",
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
      const media = crypto.randomUUID();
      let objectId: string | undefined;
      let previous: Record<string, unknown> | undefined;
      let previousEntitlement: Record<string, unknown> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_protected_analysis.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN PROTECTED ANALYSIS HELPERS\n",
        )[1]?.split("-- END PROTECTED ANALYSIS HELPERS")[0];
        assert(helpers);
        await observer.queryArray(helpers);
        previous =
          (await observer.queryObject<{ value: Record<string, unknown> }>(
            "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
          )).rows[0].value;
        previousEntitlement =
          (await observer.queryObject<{ value: Record<string, unknown> }>(
            "SELECT to_jsonb(r) AS value FROM internal.entitlement_rollout_config r WHERE config_key='current'",
          )).rows[0].value;
        await observer.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await observer.queryArray("SELECT pg_temp.seed_funded_history($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,media_enabled=TRUE,protected_analysis_enabled=TRUE",
        );
        objectId = (await observer.queryObject<{ id: string }>(
          "SELECT pg_temp.protected_ready($1,$2,$3,$4) AS id",
          [...args, media],
        )).rows[0].id;
        await observer.queryArray(
          "SELECT internal.admit_protected_observation_analysis($1,pg_temp.protected_input($2,$3,$4),repeat('a',64))",
          [...args, media],
        );
        await observer.queryArray(
          "SELECT pg_temp.funded_dispatch($1,$2,$3)",
          args,
        );
        await observer.queryArray(
          "SELECT pg_temp.protected_draft($1,$2,$3)",
          args,
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
        if (scenario.endsWith("deletion first")) {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else await fence(first);
          const pending = settle(
            second.queryObject(completeSQL, args),
          );
          await waitForBlock(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await pending).ok, false);
          await second.queryArray("ROLLBACK");
        } else {
          const saved =
            (await first.queryObject<{ receipt: unknown }>(completeSQL, [
              ...args,
            ]))
              .rows[0].receipt;
          if (scenario === "completion first") {
            const pending = settle(fence(second));
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await pending).ok);
            await second.queryArray("COMMIT");
          } else {
            const pending = settle(
              second.queryObject<{ receipt: unknown }>(completeSQL, [
                ...args,
              ]),
            );
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const result = await pending;
            assert(result.ok);
            await second.queryArray("COMMIT");
            assertEquals(result.value.rows[0].receipt, saved);
          }
        }
        const state = (await observer.queryObject<
          { results: number; intents: number; consumed: number; held: number }
        >(
          "SELECT (SELECT count(*)::int FROM internal.observation_analysis_results WHERE analysis_id=$1) AS results,(SELECT count(*)::int FROM internal.observation_analysis_intents WHERE analysis_id=$1) AS intents,(SELECT count(*)::int FROM internal.complimentary_scan_usage WHERE client_scan_id=$1 AND state='consumed') AS consumed,(SELECT count(*)::int FROM internal.complimentary_scan_usage WHERE client_scan_id=$1 AND state='held') AS held",
          [analysis],
        )).rows[0];
        assertEquals(state.held, 0);
        assertEquals(
          state.intents,
          scenario === "duplicate completion" ? 1 : 0,
        );
        assertEquals(
          state.consumed,
          scenario === "duplicate completion" || scenario === "completion first"
            ? 1
            : 0,
        );
        if (scenario === "duplicate completion") assertEquals(state.results, 1);
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          observation,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id IN ($1,$2)",
          [observation, analysis],
        );
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET admission_enabled=$1,dispatch_enabled=$2,append_enabled=$3,enrollment_enabled=$4,media_enabled=$5,protected_analysis_enabled=$6",
            [
              previous.admission_enabled,
              previous.dispatch_enabled,
              previous.append_enabled,
              previous.enrollment_enabled,
              previous.media_enabled,
              previous.protected_analysis_enabled,
            ],
          );
        }
        if (previousEntitlement) {
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [
              previousEntitlement.entitlement_mode,
              previousEntitlement.required_client_protocol,
            ],
          );
        }
        if (objectId) {
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [objectId],
          );
        }
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
