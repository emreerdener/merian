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
  throw new Error("Expected publication serialization lock not observed");
}
for (
  const scenario of [
    "consent after review",
    "consent after deletion",
    "consent after selection",
    "duplicate preparation",
    "cross-owner operation collision",
    "account deletion first",
    "preparation before deletion",
    "review before revalidation",
  ]
) {
  Deno.test({
    name: `Publication intent DB concurrency - ${scenario}`,
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
        operation = crypto.randomUUID(),
        analysis = crypto.randomUUID(),
        media = crypto.randomUUID(),
        otherOwner = crypto.randomUUID(),
        otherObservation = crypto.randomUUID(),
        otherAnalysis = crypto.randomUUID(),
        otherMedia = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "state_reader_enabled",
        "enrollment_enabled",
        "media_enabled",
        "media_reader_enabled",
        "admission_enabled",
        "dispatch_enabled",
        "append_enabled",
        "protected_analysis_enabled",
        "publication_intent_enabled",
        "rejection_api_enabled",
        "selection_api_enabled",
        "selection_enabled",
      ];
      let previousFunding: {
        entitlement_mode: string;
        required_client_protocol: number;
      } | undefined;
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
            "../../tests/observation_publication_intents.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN PUBLICATION INTENT HELPERS\n")[1].split(
            "-- END PUBLICATION INTENT HELPERS",
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
        previousFunding = (await observer.queryObject<
          { entitlement_mode: string; required_client_protocol: number }
        >("SELECT entitlement_mode,required_client_protocol FROM internal.entitlement_rollout_config WHERE config_key='current'"))
          .rows[0];
        await observer.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_publication_intent($1,$2,$3,$4)",
          [owner, observation, analysis, media],
        );
        const request = (await observer.queryObject<{ request: unknown }>(
          "SELECT pg_temp.publication_request($1,$2,$3,$4) AS request",
          [observation, analysis, operation, media],
        )).rows[0].request;
        const admit = (client: Client) =>
          client.queryObject<{ receipt: unknown }>(
            "SELECT internal.prepare_observation_publication_intent($1,$2::jsonb) AS receipt",
            [owner, JSON.stringify(request)],
          );
        if (scenario === "consent after selection") {
          // Seed a completed legacy child; selection must go through the real owner transaction.
          await observer.queryArray(
            `INSERT INTO internal.observation_analysis_results
            (analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
            SELECT $1,observation_id,2,repeat('b',64),result_snapshot,'{"schema_version":1,"captured_media":[]}',now()
            FROM internal.observation_analysis_results WHERE analysis_id=$2`,
            [otherAnalysis, analysis],
          );
          await observer.queryArray(
            `INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
            SELECT observation_id,$1,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=$2`,
            [otherAnalysis, analysis],
          );
        }
        if (scenario === "review before revalidation") await admit(observer);
        let otherRequest: unknown;
        if (scenario === "cross-owner operation collision") {
          await observer.queryArray(
            "SELECT pg_temp.seed_publication_intent($1,$2,$3,$4)",
            [otherOwner, otherObservation, otherAnalysis, otherMedia],
          );
          otherRequest = (await observer.queryObject<{ request: unknown }>(
            "SELECT pg_temp.publication_request($1,$2,$3,$4) AS request",
            [otherObservation, otherAnalysis, operation, otherMedia],
          )).rows[0].request;
        }
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario.startsWith("consent after")) {
          if (scenario === "consent after deletion") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else {
            await first.queryArray(
              "SELECT internal.lock_owned_observation_evidence($1,$2)",
              [owner, observation],
            );
            if (scenario === "consent after review") {
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
            } else {
              await first.queryArray(
                "SELECT set_config('request.jwt.claims',$1,true)",
                [JSON.stringify({ role: "authenticated", sub: owner })],
              );
              await first.queryArray(
                "SELECT public.select_owned_observation_analysis($1::jsonb,9)",
                [JSON.stringify({
                  schema_version: 1,
                  observation_id: observation,
                  analysis_id: otherAnalysis,
                  operation_id: crypto.randomUUID(),
                  expected_observation_revision: 1,
                  expected_review_revision: 0,
                })],
              );
              assertEquals(
                (await first.queryObject<{ selected_analysis_id: string }>(
                  "SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id=$1",
                  [observation],
                )).rows[0].selected_analysis_id,
                otherAnalysis,
              );
            }
          }
          const pending = settle(
            second.queryObject<
              {
                receipt: {
                  expected_observation_revision: number;
                  analysis_id: string;
                  expected_review_revision: number;
                };
              }
            >(
              "SELECT public.prepare_owned_observation_publication_consent($1,$2,$3) AS receipt",
              [owner, observation, analysis],
            ),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          if (scenario !== "consent after deletion") {
            assert(outcome.ok);
            assertEquals(
              outcome.value.rows[0].receipt.expected_observation_revision,
              2,
            );
            assertEquals(outcome.value.rows[0].receipt.analysis_id, analysis);
            assertEquals(
              outcome.value.rows[0].receipt.expected_review_revision,
              scenario === "consent after review" ? 1 : 0,
            );
            await second.queryArray("COMMIT");
          } else {
            assert(!outcome.ok);
            assertEquals(
              outcome.error,
              "analysis_history_not_found",
            );
            await second.queryArray("ROLLBACK");
          }
        } else if (scenario === "account deletion first") {
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
        } else if (scenario === "review before revalidation") {
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
          const pending = settle(
            second.queryObject(
              "SELECT internal.revalidate_observation_publication_intent($1,$2,$3)",
              [owner, observation, operation],
            ),
          );
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
        } else if (scenario === "cross-owner operation collision") {
          await admit(first);
          const pending = settle(
            second.queryObject(
              "SELECT internal.prepare_observation_publication_intent($1,$2::jsonb)",
              [otherOwner, JSON.stringify(otherRequest)],
            ),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assertEquals(outcome.error, "analysis_history_operation_conflict");
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_intents WHERE observation_id=$1",
              [otherObservation],
            )).rows[0].count,
            0,
          );
        } else {
          const original = (await admit(first)).rows[0].receipt;
          const pending = scenario === "duplicate preparation"
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
          if (scenario === "duplicate preparation") {
            assertEquals(outcome.value.rows[0].receipt, original);
          }
          await second.queryArray("COMMIT");
        }
        const count = (await observer.queryObject<{ count: number }>(
          "SELECT count(*)::int AS count FROM internal.observation_publication_intents WHERE observation_id=$1",
          [observation],
        )).rows[0].count;
        assertEquals(
          count,
          [
              "duplicate preparation",
              "review before revalidation",
              "cross-owner operation collision",
            ].includes(
              scenario,
            )
            ? 1
            : 0,
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previousFunding) {
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [
              previousFunding.entitlement_mode,
              previousFunding.required_client_protocol,
            ],
          );
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
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          otherOwner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          otherOwner,
        ]).catch(() => {});
        for (const client of [observer, first, second]) {
          await client.end().catch(() => {});
        }
      }
    },
  });
}
