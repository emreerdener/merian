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
    name: `Observation funding DB concurrency - ${scenario}`,
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
      let previous: Record<string, unknown> | undefined;
      let previousEntitlement: Record<string, unknown> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_funding.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN FUNDED ANALYSIS HELPERS\n",
        )[1]?.split("-- END FUNDED ANALYSIS HELPERS")[0];
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
          "UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3),repeat('a',64))",
          args,
        );
        await observer.queryArray(
          "SELECT pg_temp.funded_dispatch($1,$2,$3)",
          args,
        );
        await observer.queryArray(
          "SELECT pg_temp.funded_draft($1,$2,$3)",
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
            "UPDATE internal.observation_history_rollout SET admission_enabled=$1,dispatch_enabled=$2,append_enabled=$3,enrollment_enabled=$4",
            [
              previous.admission_enabled,
              previous.dispatch_enabled,
              previous.append_enabled,
              previous.enrollment_enabled,
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

for (
  const scenario of [
    "terminal during admission",
    "ingestion during admission",
    "ingestion during deletion",
  ]
) {
  Deno.test({
    name: `Observation funding DB legacy fence - ${scenario}`,
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
      let previous: Record<string, unknown> | undefined;
      let mode: Record<string, unknown> | undefined;
      try {
        for (const c of clients) await c.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_funding.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split("-- BEGIN FUNDED ANALYSIS HELPERS\n")[1]
          ?.split("-- END FUNDED ANALYSIS HELPERS")[0];
        assert(helpers);
        await observer.queryArray(helpers);
        await first.queryArray(helpers);
        previous =
          (await observer.queryObject<{ value: Record<string, unknown> }>(
            "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
          )).rows[0].value;
        mode = (await observer.queryObject<{ value: Record<string, unknown> }>(
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
          "UPDATE internal.observation_history_rollout SET admission_enabled=TRUE",
        );
        const admit =
          "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3),repeat('a',64))";
        if (scenario.endsWith("deletion")) {
          await observer.queryArray(admit, [owner, observation, analysis]);
        }
        for (const c of [first, second]) {
          await c.queryArray("BEGIN");
          await c.queryArray("SET LOCAL statement_timeout='10s'");
        }
        if (scenario.endsWith("deletion")) {
          await first.queryArray(
            "SELECT internal.lock_owned_observation_evidence($1,$2)",
            [owner, observation],
          );
          await first.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        } else await first.queryArray(admit, [owner, observation, analysis]);
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const pending = settle(
          second.queryArray(
            scenario.startsWith("terminal")
              ? "SELECT public.fail_scan_ingestion_terminal($1,$2,'fixture','fixture','fixture_failure')"
              : "SELECT public.begin_scan_ingestion($1::text,$2,'identify-multimodal','{}')",
            [analysis, owner],
          ),
        );
        await waitForBlock(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        assertEquals((await pending).ok, false);
        await second.queryArray("ROLLBACK");
        const state = (await observer.queryObject<{ state: string }>(
          "SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id=$1",
          [analysis],
        )).rows[0].state;
        assertEquals(
          state,
          scenario.endsWith("deletion") ? "released" : "held",
        );
      } finally {
        for (const c of [first, second]) {
          await c.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          observation,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id IN ($1,$2)",
          [observation, analysis],
        );
        await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
          owner,
        ]);
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          owner,
        ]);
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET admission_enabled=$1,enrollment_enabled=$2",
            [previous.admission_enabled, previous.enrollment_enabled],
          );
        }
        if (mode) {
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [mode.entitlement_mode, mode.required_client_protocol],
          );
        }
        await Promise.all(clients.map((c) => c.end()));
      }
    },
  });
}
