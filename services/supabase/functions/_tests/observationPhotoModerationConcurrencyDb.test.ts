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
    "duplicate dispatch",
    "dispatch before cancellation",
    "cancellation before dispatch",
    "dispatch before deletion",
    "account deletion first",
    "admission before deletion",
    "review before dispatch",
  ]
) {
  Deno.test({
    name: `Photo moderation DB concurrency - ${scenario}`,
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
        "publication_moderation_enabled",
        "rejection_api_enabled",
      ];
      let previousFunding: {
        entitlement_mode: string;
        required_client_protocol: number;
      } | undefined;
      let previousPolicies: { effective_plan: string; enabled: boolean }[] = [];
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
            "../../tests/observation_photo_moderation.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN PHOTO MODERATION HELPERS\n")[1].split(
            "-- END PHOTO MODERATION HELPERS",
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
        previousPolicies = (await observer.queryObject<
          { effective_plan: string; enabled: boolean }
        >("SELECT effective_plan,enabled FROM internal.ai_quota_policies WHERE operation='observation_photo_publication_moderation'"))
          .rows;
        await observer.queryArray(
          "UPDATE internal.ai_quota_policies SET enabled=true WHERE operation='observation_photo_publication_moderation'",
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_photo_moderation($1,$2,$3,$4,$5)",
          [owner, observation, analysis, media, operation],
        );
        const admit = (client: Client) =>
          client.queryObject<{ receipt: unknown }>(
            "SELECT internal.admit_publication_photo_moderation($1,$2,$3,$4,NULL,repeat('a',64)) AS receipt",
            [owner, observation, operation, media],
          );
        let prepared: { attempt_id: string; lease_token: string } | undefined;
        if (
          [
            "review before dispatch",
            "duplicate dispatch",
            "dispatch before cancellation",
            "cancellation before dispatch",
            "dispatch before deletion",
          ].includes(scenario)
        ) {
          prepared = (await admit(observer)).rows[0].receipt as {
            attempt_id: string;
            lease_token: string;
          };
        }
        const dispatch = (client: Client) =>
          client.queryObject<{ receipt: { dispatch_allowed: boolean } }>(
            "SELECT internal.dispatch_publication_photo_moderation($1,$2,$3,$4) AS receipt",
            [owner, observation, prepared!.attempt_id, prepared!.lease_token],
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
        } else if (scenario === "review before dispatch") {
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
          const pending = settle(dispatch(second));
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
        } else if (scenario === "dispatch before cancellation") {
          await dispatch(first);
          const pending = settle(
            second.queryObject(
              "SELECT internal.retire_publication_photo_moderation($1,$2,$3,$4)",
              [owner, observation, prepared!.attempt_id, prepared!.lease_token],
            ),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(!outcome.ok);
          assertEquals(outcome.error, "analysis_history_operation_conflict");
          await second.queryArray("ROLLBACK");
        } else if (scenario === "cancellation before dispatch") {
          await first.queryObject(
            "SELECT internal.retire_publication_photo_moderation($1,$2,$3,$4)",
            [owner, observation, prepared!.attempt_id, prepared!.lease_token],
          );
          const pending = settle(dispatch(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          assertEquals(outcome.value.rows[0].receipt.dispatch_allowed, false);
          await second.queryArray("COMMIT");
        } else if (scenario === "dispatch before deletion") {
          await dispatch(first);
          const pending = settle(
            second.queryObject("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          await second.queryArray("COMMIT");
        } else if (scenario === "duplicate dispatch") {
          assertEquals(
            (await dispatch(first)).rows[0].receipt.dispatch_allowed,
            true,
          );
          const pending = settle(dispatch(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assert(outcome.ok);
          assertEquals(outcome.value.rows[0].receipt.dispatch_allowed, false);
          await second.queryArray("COMMIT");
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
          "SELECT count(*)::int AS count FROM internal.observation_photo_moderation_attempts WHERE observation_id=$1",
          [observation],
        )).rows[0].count;
        assertEquals(
          count,
          [
              "duplicate admission",
              "duplicate dispatch",
              "review before dispatch",
              "dispatch before cancellation",
              "cancellation before dispatch",
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
        for (const policy of previousPolicies) {
          await observer.queryArray(
            "UPDATE internal.ai_quota_policies SET enabled=$1 WHERE operation='observation_photo_publication_moderation' AND effective_plan=$2",
            [policy.enabled, policy.effective_plan],
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
