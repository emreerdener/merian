import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const scenario of [
    "duplicate seal",
    "seal before context",
    "context before seal",
    "deletion before seal",
  ]
) {
  Deno.test({
    name: `Protected chat no-admission serializes ${scenario}`,
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
        request = crypto.randomUUID(),
        conversation = crypto.randomUUID();
      let rollout: Record<string, unknown> | undefined,
        cutover: Record<string, unknown> | undefined;
      let policies: unknown;
      try {
        for (const db of [observer, first, second]) await db.connect();
        const source = await Deno.readTextFile(
          new URL("../../tests/insight_chat_no_admission.sql", import.meta.url),
        );
        await observer.queryArray(
          source.split("-- BEGIN NO ADMISSION HELPERS\n")[1].split(
            "-- END NO ADMISSION HELPERS",
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
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ role: "authenticated", sub: owner })],
        );
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [scan],
        );
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
        );
        const ticket = (await observer.queryObject<{ ticket: unknown }>(
          "SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) ticket FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id WHERE h.observation_id=$1",
          [scan],
        )).rows[0].ticket;
        const seal = (db: Client) =>
          db.queryObject<{ result: Record<string, unknown> }>(
            "SELECT public.seal_unadmitted_insight_chat_request($1,$2,$3,$4,'Question',$5,1) result",
            [owner, scan, conversation, request, JSON.stringify(ticket)],
          );
        const admit = (db: Client) =>
          db.queryObject(
            "SELECT * FROM public.reserve_insight_chat_send_with_context($1,$2,$3,'Question',$4,$5,1)",
            [owner, conversation, scan, request, JSON.stringify(ticket)],
          );
        if (scenario !== "context before seal") {
          await observer.queryArray(
            "UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=$1",
            [scan],
          );
        }
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        if (scenario === "context before seal") {
          await admit(first);
          await first.queryArray(
            "UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=$1",
            [scan],
          );
        } else if (scenario === "deletion before seal") {
          await first.queryArray(
            "SELECT internal.lock_insight_chat_execution_subject($1,$2)",
            [owner, scan],
          );
          await first.queryArray("DELETE FROM public.scans WHERE id=$1", [
            scan,
          ]);
        } else {assertEquals(
            (await seal(first)).rows[0].result.status,
            "not_admitted",
          );}
        const pending =
          (scenario === "seal before context" ? admit(second) : seal(second))
            .then(
              (result) => ({ ok: true as const, result }),
              (error: unknown) => ({
                ok: false as const,
                code: (error as { fields?: { code?: string } }).fields?.code,
              }),
            );
        let blocked = false;
        for (let index = 0; index < 100; index++) {
          blocked = (await observer.queryObject<{ blocked: boolean }>(
            "SELECT $1::int=ANY(pg_blocking_pids($2::int)) blocked",
            [blocker, waiter],
          )).rows[0].blocked;
          if (blocked) break;
          await new Promise((resolve) => setTimeout(resolve, 20));
        }
        assert(blocked, "Expected writer-lock serialization");
        await first.queryArray("COMMIT");
        const result = await pending;
        if (
          scenario === "duplicate seal" || scenario === "context before seal"
        ) {
          assert(result.ok);
          assertEquals(
            (result.result.rows[0] as { result: { status: string } }).result
              .status,
            scenario === "duplicate seal" ? "not_admitted" : "held",
          );
        } else {
          assert(!result.ok);
          assertEquals(
            result.code,
            scenario === "deletion before seal" ? "P0002" : "55000",
          );
        }
        await second.queryArray(result.ok ? "COMMIT" : "ROLLBACK");
        const counts =
          (await observer.queryObject<{ seals: number; messages: number }>(
            "SELECT (SELECT count(*)::int FROM internal.insight_chat_execution_fences WHERE scan_id=$1 AND no_admission_reason IS NOT NULL) seals,(SELECT count(*)::int FROM public.insight_chat_messages WHERE scan_id=$1) messages",
            [scan],
          )).rows[0];
        assertEquals(counts, {
          seals: scenario.startsWith("duplicate") ||
              scenario.startsWith("seal before")
            ? 1
            : 0,
          messages: scenario === "context before seal" ? 1 : 0,
        });
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
