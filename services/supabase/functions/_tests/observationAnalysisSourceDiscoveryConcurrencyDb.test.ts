import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { parseSourceDiscovery } from "../_shared/analysisHistory/sourceDiscovery.ts";
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
  throw new Error("Expected source discovery parent lock not observed");
}
for (
  const scenario of [
    "admission first",
    "deletion first",
    "account deletion first",
    "read first",
  ]
) {
  Deno.test({
    name: `Source discovery DB concurrency - ${scenario}`,
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
      const request = {
        schema_version: 1 as const,
        observation_id: observation,
        source_analysis_id: source,
      };
      let previous: Record<string, unknown> | undefined;
      let pending: Promise<unknown> | undefined;
      try {
        for (const client of clients) await client.connect();
        const fixture = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_funding.sql",
            import.meta.url,
          ),
        );
        const helpers =
          fixture.split("-- BEGIN FUNDED ANALYSIS HELPERS\n")[1].split(
            "-- END FUNDED ANALYSIS HELPERS",
          )[0];
        for (const client of [observer, first]) {
          await client.queryArray(helpers);
        }
        previous =
          (await observer.queryObject<{ value: Record<string, unknown> }>(
            "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
          )).rows[0].value;
        await observer.queryArray("SELECT pg_temp.seed_funded_history($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET source_discovery_enabled=TRUE,append_enabled=TRUE,admission_enabled=TRUE",
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
        const read = async (client: Client) => {
          const result = await client.queryObject<{ value: unknown }>(
            "SELECT public.get_owned_observation_analysis_source($1,$2::jsonb,10) AS value",
            [owner, JSON.stringify(request)],
          );
          return parseSourceDiscovery(result.rows[0].value, request, owner);
        };
        const deletion = (client: Client) =>
          client.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
        if (scenario === "read first") {
          assertEquals((await read(first)).state, "held");
          pending = deletion(second).then(() => true, () => false);
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals(await pending, true);
          await second.queryArray("COMMIT");
          assertEquals((await read(observer)).state, "unavailable");
        } else {
          if (scenario === "admission first") {
            await first.queryArray(
              "SELECT internal.admit_observation_analysis($1,pg_temp.funded_input($2,$3,$4),repeat('a',64))",
              [owner, observation, child, source],
            );
          } else if (scenario === "account deletion first") {
            await deletion(first);
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
          const result = read(second).then(
            (value) => ({ value }),
            () => ({ value: null }),
          );
          pending = result;
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const observed = (await result).value;
          assert(observed);
          assertEquals(
            observed.state,
            scenario === "admission first" ? "existing" : "unavailable",
          );
          if (observed.state === "existing") {
            assertEquals(observed.analysis_id, child);
          }
          await second.queryArray("COMMIT");
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await pending;
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET source_discovery_enabled=$1,append_enabled=$2,admission_enabled=$3,enrollment_enabled=$4",
            [
              previous.source_discovery_enabled,
              previous.append_enabled,
              previous.admission_enabled,
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
