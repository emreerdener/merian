import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
  );
async function observeBlock(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    if (
      (await observer.queryObject<{ blocked: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
        [blocker, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected admission serialization lock not observed");
}
for (
  const scenario of [
    "duplicate admission",
    "account deletion first",
    "admission before deletion",
    "review before admission",
  ]
) {
  Deno.test({
    name: `Community admission DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const [observer, first, second] = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        operation = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "state_reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "community_authority_enabled",
        "community_admission_enabled",
        "rejection_api_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of [observer, first, second]) {
          await client.connect();
          await client.queryArray("SET statement_timeout='5s'");
          await client.queryArray(
            `SELECT set_config('request.jwt.claims','{"role":"service_role"}',false)`,
          );
        }
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_community_admission.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN COMMUNITY ADMISSION HELPERS\n")[1].split(
            "-- END COMMUNITY ADMISSION HELPERS",
          )[0],
        );
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((f) => `${f}=TRUE`).join(",")
          }`,
        );
        const analysis = (await observer.queryObject<{ analysis: string }>(
          "SELECT pg_temp.seed_admission_history($1,$2) AS analysis",
          [owner, observation],
        )).rows[0].analysis;
        const admit = (client: Client) =>
          client.queryObject<{ receipt: unknown }>(
            `SELECT internal.admit_observation_community_request($1,$2,$3,$4,1,0,public.active_taxonomy_version_id(),NULL,NULL,
          '[{"kind":"image","url":"https://example.invalid/approved.jpg","thumbnail_url":"https://example.invalid/approved.jpg","order_index":0,"duration_seconds":null,"has_audio":false}]'::jsonb) AS receipt`,
            [owner, operation, observation, analysis],
          );
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "account deletion first") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          const pending = settle(admit(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assert(outcome.error.includes("analysis_history_not_found"));
          await second.queryArray("ROLLBACK");
        } else if (scenario === "review before admission") {
          await first.queryArray(
            "SELECT set_config('request.jwt.claims',$1,true)",
            [JSON.stringify({ role: "authenticated", sub: owner })],
          );
          await first.queryArray(
            "SELECT public.review_owned_observation_analysis($1::jsonb,9)",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: analysis,
              operation_id: crypto.randomUUID(),
              expected_observation_revision: 1,
              expected_review_revision: 0,
              action: "reject",
              undo_operation_id: null,
            })],
          );
          const pending = settle(admit(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assert(outcome.error.includes("analysis_history_revision_conflict"));
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM public.explore_posts WHERE scan_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
        } else {
          const original = (await admit(first)).rows[0].receipt;
          const pending = scenario === "duplicate admission"
            ? settle(admit(second))
            : settle(
              second.queryObject<{ receipt: unknown }>(
                "SELECT public.apply_user_tombstone($1) AS receipt",
                [owner],
              ),
            );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          if (scenario === "duplicate admission") {
            assertEquals(outcome.value.rows[0].receipt, original);
          }
          await second.queryArray("COMMIT");
        }
        const count = (await observer.queryObject<{ count: number }>(
          "SELECT count(*)::int AS count FROM internal.observation_community_admissions WHERE observation_id=$1",
          [observation],
        )).rows[0].count;
        assertEquals(count, scenario === "duplicate admission" ? 1 : 0);
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((f, i) => `${f}=$${i + 1}`).join(",")
            }`,
            flags.map((f) => previous![f]),
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        for (const client of [observer, first, second]) {
          await client.end().catch(() => {});
        }
      }
    },
  });
}
