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
    "duplicate allocation",
    "duplicate ready",
    "ready before deletion",
    "deletion before ready",
    "abandon before ready",
    "ready expiry",
    "review before ready",
    "cleanup skip locked",
    "stale cleanup claim",
    "duplicate binding",
    "binding before abandon",
    "abandon before binding",
    "deletion before binding",
    "binding before deletion",
    "review before binding",
    "cleanup before binding",
  ]
) {
  Deno.test({
    name: `Public photo copy DB concurrency - ${scenario}`,
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
        "publication_copy_enabled",
        "rejection_api_enabled",
        "publication_binding_enabled",
        "community_admission_enabled",
        "community_authority_enabled",
      ];
      let copyObject: string | undefined;
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
        const helpers =
          source.split("-- BEGIN PHOTO MODERATION HELPERS\n")[1].split(
            "-- END PHOTO MODERATION HELPERS",
          )[0];
        // Each synthetic observer gets its own IP quota key. Reusing the shared
        // fixture's constant across this expanded suite exhausts unrelated tests.
        const admission =
          "internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64))";
        assertEquals(helpers.split(admission).length, 2);
        await observer.queryArray(
          helpers.replace(
            admission,
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

        const prepared = (await admit(observer)).rows[0].receipt as {
          attempt_id: string;
          lease_token: string;
        };
        const proof = (await observer.queryObject<{ proof: unknown }>(
          "SELECT pg_temp.prepare_photo_execution($1,$2,$3::jsonb) AS proof",
          [owner, observation, JSON.stringify(prepared)],
        )).rows[0].proof;
        await observer.queryArray(
          "SELECT internal.dispatch_publication_photo_moderation($1,$2,$3,$4)",
          [owner, observation, prepared.attempt_id, prepared.lease_token],
        );
        await observer.queryArray(
          "SELECT internal.complete_publication_photo_execution($1,$2,$3,$4,$5::jsonb,pg_temp.photo_execution_result())",
          [
            owner,
            observation,
            prepared.attempt_id,
            prepared.lease_token,
            JSON.stringify(proof),
          ],
        );
        type Copy = { object_id: string; lease_token: string };
        const reserve = (client: Client) =>
          client.queryObject<{ receipt: Copy }>(
            "SELECT internal.reserve_publication_photo_copy($1,$2,$3) AS receipt",
            [owner, observation, prepared.attempt_id],
          );
        let copy: Copy | undefined;
        if (scenario !== "duplicate allocation") {
          copy = (await reserve(observer)).rows[0].receipt;
        }
        copyObject = copy?.object_id;
        const complete = (client: Client) =>
          client.queryObject<{ receipt: Copy }>(
            "SELECT internal.complete_publication_photo_copy($1,$2,$3,$4,$5) AS receipt",
            [
              owner,
              observation,
              prepared.attempt_id,
              copy!.object_id,
              copy!.lease_token,
            ],
          );
        const abandon = (client: Client) =>
          client.queryArray(
            "SELECT internal.abandon_publication_photo_copy($1,$2,$3,$4,$5)",
            [
              owner,
              observation,
              prepared.attempt_id,
              copy!.object_id,
              copy!.lease_token,
            ],
          );
        const bind = (client: Client) =>
          client.queryObject<{ receipt: unknown }>(
            "SELECT internal.bind_approved_publication_photo_cohort($1,$2,$3) AS receipt",
            [owner, observation, operation],
          );
        if (scenario.includes("binding")) await complete(observer);
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (
          scenario === "duplicate binding" ||
          scenario === "binding before abandon" ||
          scenario === "binding before deletion"
        ) {
          const original = (await bind(first)).rows[0].receipt;
          const pending = settle<{ rows: unknown[] }>(
            scenario === "duplicate binding"
              ? bind(second)
              : scenario === "binding before abandon"
              ? abandon(second)
              : second.queryArray("SELECT public.apply_user_tombstone($1)", [
                owner,
              ]),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "binding before abandon") {
            assert(!result.ok);
            assertEquals(result.error, "analysis_history_operation_conflict");
            await second.queryArray("ROLLBACK");
            assertEquals(
              (await observer.queryObject<{ revoked: unknown }>(
                "SELECT revoked_at AS revoked FROM internal.publication_photo_objects WHERE object_id=$1",
                [copy!.object_id],
              )).rows[0].revoked,
              null,
            );
          } else {
            assert(result.ok);
            if (scenario === "duplicate binding") {
              assertEquals(
                (result.value.rows[0] as { receipt: unknown }).receipt,
                original,
              );
            }
            await second.queryArray("COMMIT");
          }
        } else if (
          scenario === "abandon before binding" ||
          scenario === "deletion before binding" ||
          scenario === "cleanup before binding"
        ) {
          if (scenario === "deletion before binding") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else if (scenario === "abandon before binding") {
            await abandon(first);
          } else {
            await first.queryArray(
              "UPDATE internal.publication_photo_objects SET available_at=clock_timestamp()-INTERVAL '1 second' WHERE object_id=$1",
              [copy!.object_id],
            );
            await first.queryArray(
              "SELECT internal.claim_publication_photo_erasure()",
            );
          }
          const pending = settle(bind(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(!result.ok);
          assertEquals(
            result.error,
            scenario === "deletion before binding"
              ? "analysis_history_not_found"
              : "analysis_history_operation_conflict",
          );
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM public.explore_posts WHERE scan_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
        } else if (
          scenario === "duplicate allocation" || scenario === "duplicate ready"
        ) {
          const call = scenario === "duplicate allocation" ? reserve : complete;
          const original = (await call(first)).rows[0].receipt;
          const pending = settle(call(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          assertEquals(result.value.rows[0].receipt, original);
          await second.queryArray("COMMIT");
          copy = original;
          copyObject = copy.object_id;
        } else if (scenario === "ready before deletion") {
          await complete(first);
          const pending = settle(
            second.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
        } else if (
          scenario === "deletion before ready" ||
          scenario === "abandon before ready"
        ) {
          if (scenario === "deletion before ready") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else await abandon(first);
          const pending = settle(complete(second));
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(!result.ok);
          assertEquals(
            result.error,
            scenario === "deletion before ready"
              ? "analysis_history_not_found"
              : "analysis_history_operation_conflict",
          );
          await second.queryArray("ROLLBACK");
        } else if (
          scenario === "review before ready" ||
          scenario === "review before binding"
        ) {
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
            scenario === "review before binding"
              ? bind(second)
              : complete(second),
          );
          await observeBlock(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(!result.ok);
          assertEquals(result.error, "analysis_history_revision_conflict");
          await second.queryArray("ROLLBACK");
          if (scenario === "review before ready") {
            assertEquals(
              (await observer.queryObject<{ ready: unknown }>(
                "SELECT ready_at AS ready FROM internal.observation_photo_copies WHERE attempt_id=$1",
                [prepared.attempt_id],
              )).rows[0].ready,
              null,
            );
          }
          await abandon(observer);
        } else if (scenario === "ready expiry") {
          await first.queryArray("ROLLBACK");
          await second.queryArray("ROLLBACK");
          await complete(observer);
          // Advance the eligibility deadline without sleeping ten minutes. The
          // registry allows only earlier deadlines, never extension/reuse.
          await observer.queryArray(
            "UPDATE internal.publication_photo_objects SET available_at=clock_timestamp()-INTERVAL '1 second' WHERE object_id=$1",
            [copy!.object_id],
          );
          const result = await settle(complete(observer));
          assert(!result.ok);
          const retry = await settle(reserve(observer));
          assert(!retry.ok);
          const claim = (await observer.queryObject<
            { receipt: { object_id: string; claim_token: string } }
          >("SELECT internal.claim_publication_photo_erasure() AS receipt"))
            .rows[0].receipt;
          assertEquals(claim.object_id, copy!.object_id);
          assertEquals(
            (await observer.queryObject<{ ok: boolean }>(
              "SELECT internal.finish_publication_photo_erasure($1,$2,true) AS ok",
              [copy!.object_id, claim.claim_token],
            )).rows[0].ok,
            true,
          );
        } else {
          await first.queryArray("ROLLBACK");
          await second.queryArray("ROLLBACK");
          await abandon(observer);
          // Other permanent registries from earlier cases are already erased.
          await first.queryArray("BEGIN");
          const claim = (await first.queryObject<
            { receipt: { object_id: string; claim_token: string } }
          >("SELECT internal.claim_publication_photo_erasure() AS receipt"))
            .rows[0].receipt;
          assertEquals(claim.object_id, copy!.object_id);
          if (scenario === "cleanup skip locked") {
            assertEquals(
              (await second.queryObject<{ receipt: unknown }>(
                "SELECT internal.claim_publication_photo_erasure() AS receipt",
              )).rows[0].receipt,
              null,
            );
            await first.queryArray("COMMIT");
          } else {
            await first.queryArray("COMMIT");
            await observer.queryArray(
              "UPDATE internal.publication_photo_objects SET claim_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE object_id=$1",
              [copy!.object_id],
            );
            const next =
              (await second.queryObject<{ receipt: { claim_token: string } }>(
                "SELECT internal.claim_publication_photo_erasure() AS receipt",
              )).rows[0].receipt;
            assert(next.claim_token !== claim.claim_token);
            assertEquals(
              (await observer.queryObject<{ ok: boolean }>(
                "SELECT internal.finish_publication_photo_erasure($1,$2,true) AS ok",
                [copy!.object_id, claim.claim_token],
              )).rows[0].ok,
              false,
            );
            assertEquals(
              (await observer.queryObject<{ ok: boolean }>(
                "SELECT internal.finish_publication_photo_erasure($1,$2,true) AS ok",
                [copy!.object_id, next.claim_token],
              )).rows[0].ok,
              true,
            );
          }
        }
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int AS count FROM internal.publication_photo_objects WHERE object_id=$1",
            [copy!.object_id],
          )).rows[0].count,
          1,
        );
        if (scenario.includes("deletion")) {
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_photo_copies WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
          assert(
            (await observer.queryObject<{ due: boolean }>(
              "SELECT available_at<=clock_timestamp() AS due FROM internal.publication_photo_objects WHERE object_id=$1",
              [copy!.object_id],
            )).rows[0].due,
          );
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        // Synthetic cleanup acknowledges a simulated marker; no external I/O.
        await observer.queryArray(
          "UPDATE internal.publication_photo_objects SET erased_at=clock_timestamp(),claim_token=NULL,claim_expires_at=NULL WHERE erased_at IS NULL AND object_id=$1",
          [copyObject ?? null],
        ).catch(() => {});
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
