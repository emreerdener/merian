import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let i = 0; i < 100; i++) {
    if (
      (await observer.queryObject<{ held: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS held",
        [blocker, waiter],
      )).rows[0].held
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected source admission wait not observed");
}
for (const version of [2, 3]) {
  for (
    const scenario of [
      "duplicate",
      "source first",
      "deletion first",
      "account first",
      "repeatable read replay",
      "serializable replay",
    ]
  ) {
    Deno.test({
      name: `Source execution entry DB - V${version} ${scenario}`,
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
        const ids = Array.from({ length: 5 }, () => crypto.randomUUID());
        const [owner, parent, source, child] = ids;
        let previous: Record<string, boolean> | undefined;
        let entitlement: { mode: string; protocol: number } | undefined;
        let pending: Promise<unknown> | undefined;
        try {
          for (const client of clients) await client.connect();
          const fixture = await Deno.readTextFile(
            new URL(
              "../../tests/observation_source_initial_admission.sql",
              import.meta.url,
            ),
          );
          const helpers =
            fixture.split("-- BEGIN SOURCE ADMISSION HELPERS\n")[1].split(
              "-- END SOURCE ADMISSION HELPERS",
            )[0];
          for (const client of clients) {
            await client.queryArray(helpers);
            await client.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
          }
          previous = (await observer.queryObject<Record<string, boolean>>(
            "SELECT append_enabled,media_enabled,prepared_audio_evidence_enabled,admission_enabled,protected_analysis_enabled,audio_analysis_enabled,enrollment_enabled FROM internal.observation_history_rollout WHERE singleton",
          )).rows[0];
          entitlement =
            (await observer.queryObject<{ mode: string; protocol: number }>(
              "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
            )).rows[0];
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
          );
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE",
          );
          const input = (await observer.queryObject<{ value: unknown }>(
            "SELECT pg_temp.seed_bound_admission($1,$2,$3,$4,$5,$6) AS value",
            [...ids, version],
          )).rows[0].value;
          await observer.queryArray(
            "SELECT pg_temp.admit_bound($1,$2::jsonb)",
            [owner, JSON.stringify(input)],
          );
          const admit = (client: Client) =>
            client.queryObject<{ value: Record<string, unknown> }>(
              "SELECT internal.claim_observation_analysis($1,$2,$3) AS value",
              [owner, parent, child],
            );
          if (scenario.endsWith(" replay")) {
            const isolation = scenario === "repeatable read replay"
              ? "REPEATABLE READ"
              : "SERIALIZABLE";
            await second.queryArray(`BEGIN ISOLATION LEVEL ${isolation}`);
            await second.queryArray(
              "SELECT count(*) FROM internal.observation_analysis_intents",
            );
            await observer.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [parent, owner],
            );
            let denied: string | undefined;
            await admit(second).catch((e: { fields?: { code?: string } }) => {
              denied = e.fields?.code;
            });
            assertEquals(denied, "25000");
            await second.queryArray("ROLLBACK");
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
          if (scenario === "duplicate") {
            assertEquals((await admit(first)).rows[0].value.claimed, true);
          } else if (scenario === "source first") {
            await first.queryArray(
              "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
              [`merian-analysis-source:${parent}:${source}`],
            );
          } else if (scenario === "deletion first") {
            await first.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [parent, owner],
            );
          } else {await first.queryArray(
              "SELECT public.apply_user_tombstone($1)",
              [owner],
            );}
          let code: string | undefined;
          let received: unknown;
          pending = admit(second).then((r) => {
            received = r.rows[0].value;
          }, (e: { fields?: { code?: string } }) => {
            code = e.fields?.code;
          });
          await blocked(observer, waiter, blocker);
          if (scenario === "source first") {
            const key = `merian-scan-ingestion:${child}`;
            const free = (await observer.queryObject<{ free: boolean }>(
              "SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS free",
              [key],
            )).rows[0].free;
            if (free) {
              await observer.queryArray(
                "SELECT pg_advisory_unlock(hashtextextended($1,0))",
                [key],
              );
            }
            assertEquals(free, true);
          }
          await first.queryArray("COMMIT");
          await pending;
          if (scenario === "duplicate" || scenario === "source first") {
            assertEquals(code, undefined);
            assertEquals(
              (received as { claimed: boolean }).claimed,
              scenario === "source first",
            );
            await second.queryArray("COMMIT");
            const row =
              (await observer.queryObject<{ count: string; attempt: number }>(
                "SELECT count(*)::text AS count,max(attempt_count) AS attempt FROM internal.ai_quota_reservations WHERE original_analysis_id=$1",
                [child],
              )).rows[0];
            assertEquals(row, { count: "1", attempt: 1 });
          } else {
            assertEquals(code, "P0002");
            await second.queryArray("ROLLBACK");
            assertEquals(
              (await observer.queryObject<{ count: string }>(
                "SELECT count(*)::text AS count FROM internal.ai_quota_reservations WHERE original_analysis_id=$1",
                [child],
              )).rows[0].count,
              scenario === "account first" ? "0" : "1",
            );
          }
        } finally {
          for (const client of [first, second]) {
            await client.queryArray("ROLLBACK").catch(() => {});
          }
          await pending;
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]).catch(() => {});
          if (previous) {
            await observer.queryArray(
              "UPDATE internal.observation_history_rollout SET append_enabled=$1,media_enabled=$2,prepared_audio_evidence_enabled=$3,admission_enabled=$4,protected_analysis_enabled=$5,audio_analysis_enabled=$6,enrollment_enabled=$7",
              [
                previous.append_enabled,
                previous.media_enabled,
                previous.prepared_audio_evidence_enabled,
                previous.admission_enabled,
                previous.protected_analysis_enabled,
                previous.audio_analysis_enabled,
                previous.enrollment_enabled,
              ],
            );
          }
          if (entitlement) {
            await observer.queryArray(
              "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
              [entitlement.mode, entitlement.protocol],
            );
          }
          for (const client of clients) {
            await client.end().catch(() => {});
          }
        }
      },
    });
  }
}
