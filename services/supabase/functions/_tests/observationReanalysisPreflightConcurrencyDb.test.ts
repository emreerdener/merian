import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
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
  throw new Error("Expected preflight owner fence was not observed");
}
for (
  const scenario of ["deletion first", "preflight first", "admission first"]
) {
  Deno.test({
    name: `Reanalysis recipient DB concurrency - ${scenario}`,
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
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "orchestration_enabled",
        "admission_enabled",
        "protected_analysis_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((flag) => `${flag}=TRUE`).join(",")
          }`,
        );
        const fixture = await Deno.readTextFile(
          new URL(
            "../../tests/observation_reanalysis_preflight.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          "CREATE FUNCTION pg_temp.seed_saved_observation" +
            fixture.split("CREATE FUNCTION pg_temp.seed_saved_observation")[1]
              .split("SELECT pg_temp.seed_saved_observation")[0],
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_saved_observation($1,$2)",
          [owner, observation],
        );
        await observer.queryArray(
          "UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id=$1",
          [owner],
        );
        for (const client of clients) {
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,FALSE)",
            [JSON.stringify({ sub: owner, role: "authenticated" })],
          );
        }
        await observer.queryArray("SET ROLE authenticated");
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [observation],
        );
        await observer.queryArray("RESET ROLE");
        const source = (await observer.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0].id;
        const request = JSON.stringify({
          schema_version: 1,
          observation_id: observation,
          analysis_id: analysis,
          source_analysis_id: source,
          entitlement_protocol: 3,
          identification_protocol: 6,
          history_protocol: 8,
        });
        const preflight = (client: Client) =>
          client.queryObject<{ value: { decision: string } }>(
            "SELECT public.get_owned_observation_reanalysis_preflight($1::jsonb) AS value",
            [request],
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
        if (scenario === "preflight first") {
          await first.queryArray("SET LOCAL ROLE authenticated");
          assertEquals(
            (await preflight(first)).rows[0].value.decision,
            "permission_required",
          );
          const pending = settled(
            second.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
        } else {
          if (scenario === "deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else {
            await first.queryArray(
              "SELECT internal.lock_owned_observation_evidence($1,$2)",
              [owner, observation],
            );
            await first.queryArray(
              "INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES($1,$2,$3,$4::jsonb)",
              [
                analysis,
                observation,
                owner,
                JSON.stringify({ source_analysis_id: source }),
              ],
            );
          }
          await second.queryArray("SET LOCAL ROLE authenticated");
          const pending = settled(preflight(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "deletion first") {
            assert(!result.ok);
            assertEquals(result.error, "analysis_history_not_found");
            await second.queryArray("ROLLBACK");
          } else {
            assert(result.ok);
            assertEquals(result.value.rows[0].value.decision, "recovery_only");
            await second.queryArray("COMMIT");
          }
        }
        assertEquals(
          (await observer.queryObject<{ count: string }>(
            "SELECT count(*)::text AS count FROM internal.ai_quota_reservations WHERE original_analysis_id=$1",
            [analysis],
          )).rows[0].count,
          "0",
        );
      } finally {
        for (const client of [first, second]) {
          try {
            await client.queryArray("ROLLBACK");
          } catch { /* Failed connection has no transaction. */ }
        }
        try {
          await observer.queryArray("RESET ROLE");
          if (previous) {
            await observer.queryArray(
              `UPDATE internal.observation_history_rollout SET ${
                flags.map((flag, i) => `${flag}=$${i + 1}`).join(",")
              } WHERE singleton`,
              flags.map((flag) => previous![flag]),
            );
          }
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]);
        } finally {
          for (const client of clients) await client.end();
        }
      }
    },
  });
}
