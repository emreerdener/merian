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
  throw new Error("Expected moderation settlement serialization not observed");
}
for (
  const scenario of [
    "container duplicate",
    "container deletion first",
    "container before deletion",
    "container admission first",
    "container before admission",
    "source duplicate",
    "source deletion first",
    "source before deletion",
    "source admission first",
    "source before admission",
    "completion first",
    "finalization first",
    "duplicate outcome",
    "deletion first",
    "outcome before deletion",
    "copy duplicate",
    "copy deletion first",
    "copy before deletion",
    "copy settlement duplicate",
    "copy settlement deletion first",
    "copy settlement before deletion",
    "cohort duplicate",
    "cohort abandon before complete",
    "cohort deletion before complete",
    "cohort complete before deletion",
    "cohort binding duplicate",
    "cohort binding before deletion",
    "cohort deletion before binding",
    "cohort abandon before binding",
    "cohort binding before abandon",
    "cohort binding before settlement",
    "cohort settlement before binding",
  ]
) {
  Deno.test({
    name: `Publication moderation outcome DB concurrency - ${scenario}`,
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
        analysis = crypto.randomUUID(),
        media = crypto.randomUUID(),
        operation = crypto.randomUUID();
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
        "publication_moderation_enabled",
        "publication_source_settlement_enabled",
        "publication_container_settlement_enabled",
        "publication_copy_execution_enabled",
        "publication_copy_enabled",
        "publication_copy_reservation_enabled",
        "publication_copy_binding_enabled",
        "publication_copy_settlement_enabled",
        "publication_binding_enabled",
        "community_admission_enabled",
        "community_authority_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      let funding: {
        entitlement_mode: string;
        required_client_protocol: number;
      } | undefined;
      let policies: { effective_plan: string; enabled: boolean }[] = [];
      try {
        for (const client of [observer, first, second]) {
          await client.connect();
          await client.queryArray("SET statement_timeout='5s'");
          await client.queryArray(
            `SELECT set_config('request.jwt.claims','{"role":"service_role"}',false)`,
          );
        }
        let fixture = await Deno.readTextFile(
          new URL(
            "../../tests/publication_moderation_operations.sql",
            import.meta.url,
          ),
        );
        if (scenario.startsWith("source ")) {
          fixture = fixture.replaceAll("image/jpeg", "image/heic");
        }
        if (scenario.startsWith("cohort ")) {
          fixture = fixture.replace(
            "'note','Synthetic public note'",
            "'note',NULL",
          );
        }
        await observer.queryArray(
          fixture.split("-- BEGIN PHOTO MODERATION HELPERS\n")[1].split(
            "-- END PHOTO MODERATION HELPERS",
          )[0].replace(
            "internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64))",
            "internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat(replace(observation::text,'-',''),2))",
          ),
        );
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        funding = (await observer.queryObject<
          { entitlement_mode: string; required_client_protocol: number }
        >("SELECT entitlement_mode,required_client_protocol FROM internal.entitlement_rollout_config WHERE config_key='current'"))
          .rows[0];
        policies = (await observer.queryObject<
          { effective_plan: string; enabled: boolean }
        >("SELECT effective_plan,enabled FROM internal.ai_quota_policies WHERE operation='observation_photo_publication_moderation'"))
          .rows;
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((f) => `${f}=TRUE`).join(",")
          }`,
        );
        await observer.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await observer.queryArray(
          "UPDATE internal.ai_quota_policies SET enabled=TRUE WHERE operation='observation_photo_publication_moderation'",
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_photo_moderation($1,$2,$3,$4,$5)",
          [owner, observation, analysis, media, operation],
        );
        await observer.queryArray(
          "SELECT public.admit_owned_observation_publication($1,pg_temp.publication_request($2,$3,$4,$5),$6)",
          [
            owner,
            observation,
            analysis,
            operation,
            media,
            observation.replaceAll("-", "").repeat(2),
          ],
        );
        const work =
          (await observer.queryObject<{ receipt: { work_token: string } }>(
            "SELECT public.claim_observation_publication_work($1,$2,$3) AS receipt",
            [owner, observation, operation],
          )).rows[0].receipt.work_token;
        if (
          scenario.startsWith("source ") || scenario.startsWith("container ")
        ) {
          const container = scenario.startsWith("container ");
          const mode = scenario.replace("container ", "source ");
          const attestation = container
            ? (await observer.queryObject<{ att: unknown }>(
              "SELECT jsonb_build_object('schema_version',1,'policy_version','public_photo_container_v1','source',sources->0) AS att FROM internal.observation_publication_intents WHERE operation_id=$1",
              [operation],
            )).rows[0].att
            : null;
          const finish = (client: Client) =>
            client.queryObject<
              { receipt: { finalized: boolean; reason?: string } }
            >(
              container
                ? "SELECT public.finalize_publication_container_rejection($1,$2,$3,$4,$5::jsonb) AS receipt"
                : "SELECT public.finalize_publication_photo_moderation($1,$2,$3,$4) AS receipt",
              container
                ? [
                  owner,
                  observation,
                  operation,
                  work,
                  JSON.stringify(attestation),
                ]
                : [owner, observation, operation, work],
            );
          const admit = (client: Client) =>
            client.queryObject<{ receipt: unknown }>(
              "SELECT public.admit_publication_moderation_work($1,$2,$3,$4,$5) AS receipt",
              [owner, observation, operation, work, media],
            );
          const erase = (client: Client) =>
            client.queryObject<{ receipt: unknown }>(
              "SELECT public.apply_user_tombstone($1) AS receipt",
              [owner],
            );
          const firstPID = (await first.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          const secondPID = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          if (mode === "source deletion first") await erase(first);
          else if (mode === "source admission first") await admit(first);
          else {assertEquals(
              (await finish(first)).rows[0].receipt.reason,
              container
                ? "public_container_rejected"
                : "unsupported_source_type",
            );}
          const pending = settle(
            mode === "source before deletion"
              ? erase(second)
              : mode === "source before admission"
              ? admit(second)
              : finish(second),
          );
          await observeBlock(observer, secondPID, firstPID);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (
            mode === "source deletion first" ||
            mode === "source before admission" ||
            (container && mode === "source admission first")
          ) {
            assert(!result.ok);
            assert(
              result.error.includes(
                container && mode === "source admission first"
                  ? "analysis_history_operation_conflict"
                  : "analysis_history_not_found",
              ),
            );
            await second.queryArray("ROLLBACK");
          } else {
            assert(result.ok);
            await second.queryArray("COMMIT");
            if (mode === "source admission first") {
              assertEquals(result.value.rows[0].receipt, { finalized: false });
            }
          }
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_moderation_outcomes WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            mode.includes("deletion") ||
              mode === "source admission first"
              ? 0
              : 1,
          );
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_photo_moderation_attempts WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            mode === "source admission first" ? 1 : 0,
          );
          return;
        }
        const receipt = (await observer.queryObject<
          { receipt: { attempt_id: string; lease_token: string } }
        >(
          "SELECT public.admit_publication_moderation_work($1,$2,$3,$4,$5) AS receipt",
          [owner, observation, operation, work, media],
        )).rows[0].receipt;
        const proof = (await observer.queryObject<{ proof: unknown }>(
          "SELECT pg_temp.photo_execution_proof($1::jsonb) AS proof",
          [JSON.stringify(receipt)],
        )).rows[0].proof;
        // The full receipt's source is required by the SQL proof helper above.
        const result = (await observer.queryObject<{ result: unknown }>(
          "SELECT pg_temp.photo_execution_result() AS result",
        )).rows[0].result;
        const advance = (
          client: Client,
          action: string,
          payload: unknown = {},
        ) =>
          client.queryObject<{ receipt: unknown }>(
            "SELECT public.advance_publication_moderation_work($1,$2,$3,$4,$5,$6,$7,$8::jsonb) AS receipt",
            [
              owner,
              observation,
              operation,
              work,
              receipt.attempt_id,
              receipt.lease_token,
              action,
              JSON.stringify(payload),
            ],
          );
        await advance(observer, "prepare", { proof });
        await advance(observer, "dispatch");
        const finalize = (client: Client) =>
          client.queryObject<
            {
              receipt: {
                finalized: boolean;
                status?: string;
                reason?: string | null;
              };
            }
          >(
            "SELECT public.finalize_publication_photo_moderation($1,$2,$3,$4) AS receipt",
            [owner, observation, operation, work],
          );
        const complete = (client: Client) =>
          advance(client, "complete", { proof, result });
        const erase = (client: Client) =>
          client.queryObject<{ receipt: unknown }>(
            "SELECT public.apply_user_tombstone($1) AS receipt",
            [owner],
          );
        if (!["completion first", "finalization first"].includes(scenario)) {
          await complete(observer);
        }
        const copy = scenario.startsWith("copy ") ||
          scenario.startsWith("cohort ");
        const claimCopy = (client: Client) =>
          client.queryObject<{ receipt: { claimed: boolean } }>(
            "SELECT public.claim_publication_copy_work($1,$2,$3) AS receipt",
            [owner, observation, operation],
          );
        if (copy) await finalize(observer);
        if (scenario.startsWith("copy settlement")) {
          const claimed =
            (await observer.queryObject<{ receipt: { work_token: string } }>(
              "SELECT public.claim_publication_copy_work($1,$2,$3) AS receipt",
              [owner, observation, operation],
            )).rows[0].receipt;
          const finishCopy = (client: Client) =>
            client.queryObject<{ receipt: unknown }>(
              "SELECT public.finalize_publication_copy_work($1,$2,$3,$4) AS receipt",
              [owner, observation, operation, claimed.work_token],
            );
          const firstPID = (await first.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          const secondPID = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          let original: unknown;
          if (scenario === "copy settlement deletion first") await erase(first);
          else original = (await finishCopy(first)).rows[0].receipt;
          const pending = settle(
            scenario === "copy settlement before deletion"
              ? erase(second)
              : finishCopy(second),
          );
          await observeBlock(observer, secondPID, firstPID);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "copy settlement deletion first") {
            assert(!result.ok);
            assert(result.error.includes("analysis_history_not_found"));
            await second.queryArray("ROLLBACK");
          } else {
            assert(result.ok);
            await second.queryArray("COMMIT");
            if (scenario === "copy settlement duplicate") {
              assertEquals(result.value.rows[0].receipt, original);
            }
          }
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_copy_outcomes WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            scenario.includes("deletion") ? 0 : 1,
          );
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_copy_work WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            0,
          );
          return;
        }
        if (scenario.startsWith("cohort ")) {
          const claim =
            (await observer.queryObject<{ receipt: { work_token: string } }>(
              "SELECT public.claim_publication_copy_work($1,$2,$3) AS receipt",
              [owner, observation, operation],
            )).rows[0].receipt;
          const scope = [owner, observation, operation, claim.work_token];
          type Member = {
            attempt_id: string;
            object_id: string;
            lease_token: string;
          };
          const reserve = (client: Client) =>
            client.queryObject<
              { receipt: { expires_at: string; copies: Member[] } }
            >(
              "SELECT public.reserve_publication_copy_cohort($1,$2,$3,$4) AS receipt",
              scope,
            );
          const saved = scenario === "cohort duplicate"
            ? null
            : (await reserve(observer)).rows[0].receipt;
          const completeCopy = (client: Client) =>
            client.queryObject<{ receipt: unknown }>(
              "SELECT public.complete_publication_copy_cohort_photo($1,$2,$3,$4,$5,$6,$7) AS receipt",
              [
                ...scope,
                saved!.copies[0].attempt_id,
                saved!.copies[0].object_id,
                saved!.copies[0].lease_token,
              ],
            );
          const abandon = (client: Client) =>
            client.queryObject<{ receipt: unknown }>(
              "SELECT public.abandon_publication_copy_cohort($1,$2,$3,$4) AS receipt",
              scope,
            );
          if (scenario.includes("binding")) {
            await completeCopy(observer);
            const bind = (client: Client) =>
              client.queryObject<{ receipt: unknown }>(
                "SELECT public.bind_publication_copy_cohort($1,$2,$3,$4) AS receipt",
                scope,
              );
            const firstPID = (await first.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() AS pid",
            )).rows[0].pid;
            const secondPID = (await second.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() AS pid",
            )).rows[0].pid;
            await first.queryArray("BEGIN");
            await second.queryArray("BEGIN");
            const settleCopy = (client: Client) =>
              client.queryObject<{ receipt: unknown }>(
                "SELECT public.finalize_publication_copy_work($1,$2,$3,$4) AS receipt",
                scope,
              );
            let original: unknown;
            if (scenario === "cohort settlement before binding") {
              assertEquals((await settleCopy(first)).rows[0].receipt, {
                finalized: false,
              });
            } else if (scenario === "cohort deletion before binding") {
              await erase(first);
            } else if (scenario === "cohort abandon before binding") {
              await abandon(first);
            } else original = (await bind(first)).rows[0].receipt;
            const pending = settle(
              scenario === "cohort binding before deletion"
                ? erase(second)
                : scenario === "cohort binding before settlement"
                ? settleCopy(second)
                : scenario === "cohort binding before abandon"
                ? abandon(second)
                : bind(second),
            );
            await observeBlock(observer, secondPID, firstPID);
            await first.queryArray("COMMIT");
            const outcome = await pending;
            if (
              scenario === "cohort deletion before binding" ||
              scenario === "cohort abandon before binding"
            ) {
              assert(!outcome.ok);
              assert(
                outcome.error.includes(
                  scenario.includes("deletion")
                    ? "analysis_history_not_found"
                    : "analysis_history_operation_conflict",
                ),
              );
              await second.queryArray("ROLLBACK");
            } else {
              assert(outcome.ok);
              await second.queryArray("COMMIT");
              if (scenario === "cohort binding duplicate") {
                assertEquals(outcome.value.rows[0].receipt, original);
              }
              if (scenario === "cohort binding before settlement") {
                assertEquals(outcome.value.rows[0].receipt, {
                  finalized: true,
                  status: "admitted",
                  reason: null,
                  object_ids: [],
                });
              }
              if (scenario === "cohort binding before abandon") {
                assertEquals(outcome.value.rows[0].receipt, {
                  abandoned: false,
                });
              }
            }
            assertEquals(
              (await observer.queryObject<{ count: number }>(
                "SELECT count(*)::int AS count FROM internal.observation_photo_publications WHERE operation_id=$1",
                [operation],
              )).rows[0].count,
              scenario.includes("deletion") ||
                scenario === "cohort abandon before binding"
                ? 0
                : 1,
            );
            return;
          }
          const firstPID = (await first.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          const secondPID = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          let original: unknown;
          if (scenario === "cohort duplicate") {
            original = (await reserve(first)).rows[0].receipt;
          } else if (scenario === "cohort abandon before complete") {
            await abandon(first);
          } else if (scenario === "cohort deletion before complete") {
            await erase(first);
          } else await completeCopy(first);
          const pending = settle(
            scenario === "cohort duplicate"
              ? reserve(second)
              : scenario === "cohort complete before deletion"
              ? erase(second)
              : completeCopy(second),
          );
          await observeBlock(observer, secondPID, firstPID);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          if (
            scenario === "cohort duplicate" ||
            scenario === "cohort complete before deletion"
          ) {
            assert(outcome.ok);
            await second.queryArray("COMMIT");
            if (scenario === "cohort duplicate") {
              assertEquals(outcome.value.rows[0].receipt, original);
            }
          } else {
            assert(!outcome.ok);
            assert(
              outcome.error.includes(
                scenario.includes("deletion")
                  ? "analysis_history_not_found"
                  : "analysis_history_operation_conflict",
              ),
            );
            await second.queryArray("ROLLBACK");
          }
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_publication_copy_cohorts WHERE operation_id=$1",
              [operation],
            )).rows[0].count,
            scenario.includes("deletion") ? 0 : 1,
          );
          return;
        }
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "copy deletion first") await erase(first);
        else if (copy) {
          assertEquals((await claimCopy(first)).rows[0].receipt.claimed, true);
        } else if (scenario === "completion first") await complete(first);
        else if (scenario === "deletion first") await erase(first);
        else {assertEquals(
            (await finalize(first)).rows[0].receipt.finalized,
            scenario !== "finalization first",
          );}
        const pending = settle(
          scenario === "copy before deletion"
            ? erase(second)
            : copy
            ? claimCopy(second)
            : scenario === "finalization first"
            ? complete(second)
            : scenario === "outcome before deletion"
            ? erase(second)
            : finalize(second),
        );
        await observeBlock(observer, secondPid, firstPid);
        await first.queryArray("COMMIT");
        const outcome = await pending;
        if (
          scenario === "deletion first" || scenario === "copy deletion first"
        ) {
          assert(!outcome.ok);
          assert(outcome.error.includes("analysis_history_not_found"));
          await second.queryArray("ROLLBACK");
        } else {
          assert(outcome.ok);
          await second.queryArray("COMMIT");
          if (scenario === "copy duplicate") {
            assertEquals(outcome.value.rows[0].receipt, { claimed: false });
            assertEquals(
              (await claimCopy(observer)).rows[0].receipt.claimed,
              false,
            );
          }
          if (!scenario.includes("deletion")) {
            assertEquals((await finalize(observer)).rows[0].receipt, {
              finalized: true,
              status: "photos_approved",
              reason: null,
            });
          }
        }
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int AS count FROM internal.observation_publication_moderation_outcomes WHERE operation_id=$1",
            [operation],
          )).rows[0].count,
          scenario.includes("deletion") ? 0 : 1,
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (funding) {
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [funding.entitlement_mode, funding.required_client_protocol],
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
        for (const policy of policies) {
          await observer.queryArray(
            "UPDATE internal.ai_quota_policies SET enabled=$1 WHERE operation='observation_photo_publication_moderation' AND effective_plan=$2",
            [policy.enabled, policy.effective_plan],
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
