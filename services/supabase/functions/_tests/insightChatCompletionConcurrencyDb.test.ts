import { assert, assertEquals } from "@std/assert";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const scenario of [
    "refusal before replay",
    "refusal before deletion",
    "deletion before refusal",
  ]
) {
  Deno.test({
    name: `Atomic Insight local completion serializes ${scenario}`,
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
        const conversation = crypto.randomUUID();
        assertEquals(
          (await observer.queryObject<{ id: string }>(
            "SELECT internal.insight_chat_assistant_id($1,$2)::text id",
            [conversation, request],
          )).rows[0].id,
          await deriveFieldChatAssistantMessageId(conversation, request),
        );
        const refuse = (db: Client) =>
          db.queryObject<{ receipt: unknown }>(
            "SELECT public.admit_insight_chat_local_refusal($1,$2,$3,'Question',$4,NULL,1,'dangerous_handling') receipt",
            [owner, conversation, scan, request],
          );
        const erase = (db: Client) =>
          db.queryObject("SELECT public.request_scan_deletion($1,$2)", [
            scan,
            owner,
          ]);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        if (scenario === "deletion before refusal") await erase(first);
        else await refuse(first);
        const pending = (scenario === "refusal before deletion"
          ? erase(second)
          : refuse(second)).then(
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
        if (scenario === "deletion before refusal") {
          assert(!result.ok);
          assertEquals(result.code, "P0002");
          assert(result.message.includes("field_chat_subject_not_found"));
          await second.queryArray("ROLLBACK");
        } else {
          assert(result.ok);
          await second.queryArray("COMMIT");
        }
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM public.insight_chat_messages WHERE user_id=$1 AND role='user' AND client_message_id=$2",
            [owner, request],
          )).rows[0].count,
          scenario === "deletion before refusal" ? 0 : 1,
        );
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM internal.ai_quota_reservations WHERE user_id=$1",
            [owner],
          )).rows[0].count,
          0,
        );
        if (scenario === "refusal before replay") {
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT sum(admitted_count)::int count FROM internal.field_chat_daily_admissions WHERE user_id=$1",
              [owner],
            )).rows[0].count,
            1,
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
