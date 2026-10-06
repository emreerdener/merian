import { assert, assertEquals } from "@std/assert";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const scenario of [
    "enrollment before admission",
    "enrollment before commit",
    "commit before enrollment",
  ]
) {
  Deno.test({
    name: `Legacy Insight/history boundary serializes ${scenario}`,
    ignore: !url,
    async fn() {
      assert(
        url &&
          ["127.0.0.1", "localhost", "[::1]"].includes(new URL(url).hostname),
      );
      const [observer, first, second] = [
        new Client(url),
        new Client(url),
        new Client(url),
      ];
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        request = crypto.randomUUID();
      let rollout: Record<string, unknown> | undefined,
        cutover: Record<string, unknown> | undefined;
      let policies: unknown;
      try {
        for (const db of [observer, first, second]) await db.connect();
        const helpers = await Deno.readTextFile(
          new URL(
            "../../tests/insight_chat_execution_fence.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          helpers.split("-- BEGIN EXECUTION FENCE HELPERS\n")[1].split(
            "-- END EXECUTION FENCE HELPERS",
          )[0],
        );
        rollout =
          (await observer.queryObject<{ data: Record<string, unknown> }>(
            "SELECT to_jsonb(r) data FROM internal.observation_history_rollout r",
          )).rows[0].data;
        cutover =
          (await observer.queryObject<{ data: Record<string, unknown> }>(
            "SELECT to_jsonb(r) data FROM internal.field_chat_admission_cutover r",
          )).rows[0].data;
        policies = (await observer.queryObject<{ data: unknown }>(
          "SELECT jsonb_agg(to_jsonb(p)) data FROM internal.ai_quota_policies p WHERE operation='insight_chat_reply'",
        )).rows[0].data;
        for (const db of [observer, first, second]) {
          await db.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
          );
        }
        await observer.queryArray("SELECT pg_temp.seed_fenced_chat($1,$2)", [
          owner,
          scan,
        ]);
        await observer.queryArray("SELECT pg_temp.open_fenced_chat()");
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE",
        );
        const conversation = crypto.randomUUID();
        assertEquals(
          (await observer.queryObject<{ id: string }>(
            "SELECT internal.insight_chat_assistant_id($1,$2)::text id",
            [conversation, request],
          )).rows[0].id,
          await deriveFieldChatAssistantMessageId(conversation, request),
          "SQL enrollment must recognize the exact assistant ID written by the existing TypeScript handler",
        );
        const legacy = (db: Client) =>
          db.queryObject(
            "SELECT * FROM public.reserve_field_chat_send($1,$2,'insight',$3,'Question',$4)",
            [owner, conversation, scan, request],
          );
        let quota: { reservation_id: string; lease_token: string } | undefined;
        if (scenario !== "enrollment before admission") {
          await legacy(observer);
          quota = (await observer.queryObject<
            { reservation_id: string; lease_token: string }
          >(
            "SELECT reservation_id,lease_token FROM internal.reserve_ai_quota_core($1,'insight_chat_reply',$2,repeat('a',64),$3,FALSE,NULL,FALSE)",
            [owner, request, scan],
          )).rows[0];
        }
        const commit = (db: Client) => {
          assert(quota);
          return db.queryObject(
            "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'committed')",
            [quota.reservation_id, owner, quota.lease_token],
          );
        };
        const enroll = async (db: Client) => {
          await db.queryArray(
            "SELECT set_config('request.jwt.claims',$1,FALSE)",
            [JSON.stringify({ role: "authenticated", sub: owner })],
          );
          return await db.queryObject(
            "SELECT public.enroll_owned_observation_history($1,9)",
            [scan],
          );
        };
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        if (scenario === "commit before enrollment") await commit(first);
        else await enroll(first);
        const pending = (scenario === "commit before enrollment"
          ? enroll(second)
          : scenario === "enrollment before commit"
          ? commit(second)
          : legacy(second)).then(
            (result) => ({ ok: true as const, result }),
            (error) => ({
              ok: false as const,
              code: error.fields?.code as string,
              message: error.message as string,
            }),
          );
        let blocked = false;
        for (let n = 0; n < 100; n++) {
          blocked = (await observer.queryObject<{ blocked: boolean }>(
            "SELECT $1::int=ANY(pg_blocking_pids($2::int)) blocked",
            [blocker, waiter],
          )).rows[0].blocked;
          if (blocked) {
            break;
          }
          await new Promise((resolve) =>
            setTimeout(resolve, 20)
          );
        }
        assert(blocked, "Expected deterministic row-lock serialization");
        await first.queryArray("COMMIT");
        const result = await pending;
        assert(!result.ok);
        assertEquals(result.code, "55000");
        assert(result.message.includes(
          scenario === "commit before enrollment"
            ? "analysis_history_chat_in_progress"
            : "field_chat_context_required",
        ));
        await second.queryArray("ROLLBACK");
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM internal.observation_histories WHERE observation_id=$1",
            [scan],
          )).rows[0].count,
          scenario === "commit before enrollment" ? 0 : 1,
        );
        if (quota) {
          assertEquals(
            (await observer.queryObject<{ state: string }>(
              "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
              [quota.reservation_id],
            )).rows[0].state,
            scenario === "commit before enrollment" ? "committed" : "reserved",
          );
        }
      } finally {
        for (const db of [first, second]) {
          await db.queryArray("ROLLBACK").catch(() => {});
        }
        try {
          await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
            scan,
          ]);
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            owner,
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]);
          if (rollout) {
            await observer.queryArray(
              "UPDATE internal.observation_history_rollout SET chat_context_enabled=$1,chat_execution_enabled=$2,reader_enabled=$3,enrollment_enabled=$4,saved_import_enabled=$5",
              [
                rollout.chat_context_enabled,
                rollout.chat_execution_enabled,
                rollout.reader_enabled,
                rollout.enrollment_enabled,
                rollout.saved_import_enabled,
              ],
            );
          }
          if (cutover) {
            await observer.queryArray(
              "UPDATE internal.field_chat_admission_cutover SET (seeded_at,not_before_utc,activated_at,activated_candidate_sha,activated_migration_sha256,activated_explore_bundle_sha256,activated_insight_bundle_sha256,activated_species_dictionary_bundle_sha256,beta_early_activation_at,beta_original_not_before_utc)=(SELECT seeded_at,not_before_utc,activated_at,activated_candidate_sha,activated_migration_sha256,activated_explore_bundle_sha256,activated_insight_bundle_sha256,activated_species_dictionary_bundle_sha256,beta_early_activation_at,beta_original_not_before_utc FROM jsonb_populate_record(NULL::internal.field_chat_admission_cutover,$1))",
              [JSON.stringify(cutover)],
            );
          }
          if (policies) {
            await observer.queryArray(
              "UPDATE internal.ai_quota_policies p SET daily_limit=r.daily_limit,user_window_limit=r.user_window_limit,ip_window_limit=r.ip_window_limit FROM jsonb_populate_recordset(NULL::internal.ai_quota_policies,$1) r WHERE p.operation=r.operation AND p.effective_plan=r.effective_plan",
              [JSON.stringify(policies)],
            );
          }
        } finally {
          for (const db of [observer, first, second]) await db.end();
        }
      }
    },
  });
}
