import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
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
  throw new Error("Expected account deletion serialization lock not observed");
}
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
  );
for (const mutation of ["selection", "rejection"] as const) {
  for (const deletionFirst of [false, true]) {
    Deno.test({
      name: `Scientific retention DB concurrency - ${mutation}, deletion ${
        deletionFirst ? "first" : "last"
      }`,
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
          other = crypto.randomUUID();
        const flags = [
          "reader_enabled",
          "enrollment_enabled",
          "state_reader_enabled",
          "selection_enabled",
          "selection_api_enabled",
          "rejection_api_enabled",
        ];
        let previous: Record<string, boolean> | undefined;
        try {
          for (const client of clients) await client.connect();
          const source = await Deno.readTextFile(
            new URL(
              "../../tests/observation_scientific_retention.sql",
              import.meta.url,
            ),
          );
          await observer.queryArray(
            source.split("-- BEGIN SCIENTIFIC RETENTION HELPERS\n")[1].split(
              "-- END SCIENTIFIC RETENTION HELPERS",
            )[0],
          );
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
          const analysis = (await observer.queryObject<{ id: string }>(
            "SELECT pg_temp.seed_retention($1,$2) AS id",
            [owner, observation],
          )).rows[0].id;
          await observer.queryArray(
            "INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at) SELECT $1,observation_id,2,analysis_id,repeat('b',64),result_snapshot || '{\"ai_confidence_score\":0.17}'::jsonb,evidence_manifest,now() FROM internal.observation_analysis_results WHERE analysis_id=$2",
            [other, analysis],
          );
          await observer.queryArray(
            "INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) SELECT observation_id,$1,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=$2",
            [other, analysis],
          );
          for (const client of clients) {
            await client.queryArray(
              "SELECT set_config('request.jwt.claims',$1,FALSE)",
              [JSON.stringify({ sub: owner, role: "service_role" })],
            );
          }
          const request = {
            schema_version: 1,
            observation_id: observation,
            analysis_id: mutation === "selection" ? other : analysis,
            operation_id: crypto.randomUUID(),
            expected_observation_revision: 1,
            expected_review_revision: 0,
            ...(mutation === "rejection"
              ? { action: "reject", undo_operation_id: null }
              : {}),
          };
          const mutate = (client: Client) =>
            client.queryArray(
              mutation === "selection"
                ? "SELECT public.select_owned_observation_analysis($1::jsonb,9)"
                : "SELECT public.review_owned_observation_analysis($1::jsonb,9)",
              [JSON.stringify(request)],
            );
          const detach = (client: Client) =>
            client.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
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
          await (deletionFirst ? detach(first) : mutate(first));
          const pending = settled(
            deletionFirst ? mutate(second) : detach(second),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (deletionFirst) {
            assert(!result.ok);
            assertEquals(result.error, "analysis_history_not_found");
            await second.queryArray("ROLLBACK");
          } else {
            assert(result.ok);
            await second.queryArray("COMMIT");
          }
          const retained = (await observer.queryObject<
            {
              score: string;
              rank: string;
              owner: string | null;
              original: boolean;
              children: number;
            }
          >(
            "SELECT retained_identification->>'ai_confidence_score' AS score,retained_identification->>'rank' AS rank,user_id AS owner,(ai_confidence_score=0.9) AS original,(SELECT count(*)::int FROM internal.observation_analysis_results WHERE observation_id=$1) AS children FROM public.scans WHERE id=$1",
            [observation],
          )).rows[0];
          assertEquals(retained, {
            score: !deletionFirst && mutation === "selection" ? "0.17" : "0.42",
            rank: !deletionFirst && mutation === "rejection"
              ? "unresolved_biological"
              : "family",
            owner: null,
            original: true,
            children: 0,
          });
        } finally {
          for (const client of [first, second]) {
            await client.queryArray("ROLLBACK").catch(() => {});
          }
          if (previous) {
            await observer.queryArray(
              `UPDATE internal.observation_history_rollout SET ${
                flags.map((flag, i) => `${flag}=$${i + 1}`).join(",")
              }`,
              flags.map((flag) => previous![flag]),
            );
          }
          await observer.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
          ).catch(() => {});
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]).catch(() => {});
          for (const client of clients) await client.end().catch(() => {});
        }
      },
    });
  }
}
