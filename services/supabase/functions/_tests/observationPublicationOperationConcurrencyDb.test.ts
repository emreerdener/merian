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
    "duplicate work claim",
    "binding before work claim",
    "deletion before work claim",
    "work claim before deletion",
    "owner capacity across observations",
    "account deletion first",
    "admission before deletion",
    "review before admission",
  ]
) {
  Deno.test({
    name: `Publication operation DB concurrency - ${scenario}`,
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
        media = crypto.randomUUID();
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
        "publication_operation_enabled",
        "publication_execution_enabled",
        "rejection_api_enabled",
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
          )[0].replace(
            "VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW());",
            "VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW()) ON CONFLICT(id) DO NOTHING;",
          ).replace(
            "PERFORM pg_temp.seed_history_append(owner_id,observation);",
            "PERFORM pg_temp.seed_history_append(owner_id,observation); IF EXISTS(SELECT 1 FROM public.user_adult_eligibility_receipts WHERE user_id=owner_id) THEN RETURN; END IF;",
          ).replace(
            "internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64))",
            "internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat(replace(observation::text,'-',''),2))",
          ),
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
            "SELECT public.admit_owned_observation_publication($1,$2::jsonb,repeat('a',64)) AS receipt",
            [owner, JSON.stringify(request)],
          );
        const claim = (client: Client) =>
          client.queryObject<
            { receipt: { claimed: boolean; work_token?: string } }
          >(
            "SELECT public.claim_observation_publication_work($1,$2,$3) AS receipt",
            [owner, observation, operation],
          );
        if (scenario.includes("work claim")) await admit(observer);
        let otherRequest: unknown;
        if (scenario === "owner capacity across observations") {
          const otherObservation = crypto.randomUUID(),
            otherAnalysis = crypto.randomUUID(),
            otherMedia = crypto.randomUUID();
          await observer.queryArray(
            "SELECT pg_temp.seed_publication_intent($1,$2,$3,$4)",
            [owner, otherObservation, otherAnalysis, otherMedia],
          );
          otherRequest = (await observer.queryObject<{ request: unknown }>(
            "SELECT pg_temp.publication_request($1,$2,$3,$4) AS request",
            [
              otherObservation,
              otherAnalysis,
              crypto.randomUUID(),
              otherMedia,
            ],
          )).rows[0].request;
          for (let n = 0; n < 7; n++) {
            await observer.queryArray(
              "SELECT public.admit_owned_observation_publication($1,$2::jsonb || jsonb_build_object('operation_id',$3::uuid),repeat('a',64))",
              [owner, JSON.stringify(request), crypto.randomUUID()],
            );
          }
        }
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "binding before work claim") {
          // Model the final binder transaction; ordered source/approval checks
          // are independently covered by the photo binding integration suite.
          await first.queryArray(
            "SELECT internal.lock_owned_observation_evidence($1,$2)",
            [owner, observation],
          );
          await first.queryArray(
            'INSERT INTO internal.observation_photo_publications(operation_id,object_ids,receipt) VALUES($1,ARRAY[$2::uuid],\'{"status":"admitted"}\')',
            [operation, crypto.randomUUID()],
          );
          const pending = settle(claim(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          assertEquals(outcome.value.rows[0].receipt, { claimed: false });
          await second.queryArray("COMMIT");
        } else if (scenario === "duplicate work claim") {
          const original = (await claim(first)).rows[0].receipt;
          assert(original.claimed);
          const pending = settle(claim(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          assertEquals(outcome.value.rows[0].receipt, { claimed: false });
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ work_token: string }>(
              "SELECT work_token FROM internal.observation_publication_work WHERE operation_id=$1",
              [operation],
            )).rows[0].work_token,
            original.work_token,
          );
        } else if (scenario === "deletion before work claim") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          const pending = settle(claim(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assert(outcome.error.includes("analysis_history_not_found"));
          await second.queryArray("ROLLBACK");
        } else if (scenario === "work claim before deletion") {
          const original = (await claim(first)).rows[0].receipt;
          assert(original.claimed);
          const pending = settle(
            second.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_work WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            0,
          );
          const late = await settle(first.queryArray(
            "SELECT public.release_observation_publication_work($1,$2,$3,$4)",
            [owner, observation, operation, original.work_token],
          ));
          assert(!late.ok);
          assert(late.error.includes("analysis_history_not_found"));
        } else if (scenario === "owner capacity across observations") {
          const original = (await admit(first)).rows[0].receipt;
          const pending = settle(
            second.queryObject(
              "SELECT public.admit_owned_observation_publication($1,$2::jsonb,repeat('b',64))",
              [owner, JSON.stringify(otherRequest)],
            ),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assert(outcome.error.includes("analysis_history_unavailable"));
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_operations WHERE owner_id=$1",
              [owner],
            )).rows[0].count,
            8,
          );
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET publication_operation_enabled=FALSE",
          );
          assertEquals((await admit(first)).rows[0].receipt, original);
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
          "SELECT count(*)::int AS count FROM internal.observation_publication_operations WHERE observation_id=$1",
          [observation],
        )).rows[0].count;
        assertEquals(
          count,
          scenario === "owner capacity across observations" ? 8 : [
              "duplicate admission",
              "duplicate work claim",
              "binding before work claim",
            ].includes(scenario)
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
        for (const client of [observer, first, second]) {
          await client.end().catch(() => {});
        }
      }
    },
  });
}
