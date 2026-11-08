import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const scenario of [
    "duplicate",
    "deletion",
    "refund before binding",
    "duplicate dispatch",
    "refund before dispatch",
    "deletion before dispatch",
  ]
) {
  Deno.test({
    name: `Protected Insight execution fence serializes ${scenario}`,
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
      const reserve = (db: Client) =>
        db.queryObject<{ result: Record<string, unknown> }>(
          "SELECT public.reserve_protected_insight_chat_quota($1,$2,$3,'Question',NULL,1,repeat('a',64)) result",
          [owner, scan, request],
        );
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
        let quota: { reservation_id: string; lease_token: string } | undefined;
        if (
          scenario === "refund before binding" || scenario.includes("dispatch")
        ) {
          await reserve(observer);
          quota = (await observer.queryObject<
            { reservation_id: string; lease_token: string }
          >(
            "SELECT reservation_id,lease_token FROM internal.insight_chat_execution_fences WHERE scan_id=$1 AND client_message_id=$2",
            [scan, request],
          )).rows[0];
        }
        if (scenario.includes("dispatch")) {
          assert(quota);
          await observer.queryArray(
            "SELECT * FROM public.reserve_protected_insight_chat_send_with_context($1,$2,$3,'Question',$4,NULL,1,$5,$6)",
            [
              owner,
              crypto.randomUUID(),
              scan,
              request,
              quota.reservation_id,
              quota.lease_token,
            ],
          );
        }
        const dispatch = (db: Client) => {
          assert(quota);
          return db.queryObject<{ result: Record<string, unknown> }>(
            "SELECT public.grant_protected_insight_chat_dispatch($1,$2,$3,$4,$5) result",
            [owner, scan, request, quota.reservation_id, quota.lease_token],
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
        if (scenario === "duplicate") {
          assertEquals(
            (await reserve(first)).rows[0].result.status,
            "reserved",
          );
        } else if (scenario === "duplicate dispatch") {
          assertEquals(
            (await dispatch(first)).rows[0].result.status,
            "dispatch_granted",
          );
        } else if (scenario.startsWith("deletion")) {
          await first.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await first.queryArray("DELETE FROM public.scans WHERE id=$1", [
            scan,
          ]);
        } else {
          assert(quota);
          await first.queryArray(
            "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'refunded')",
            [quota.reservation_id, owner, quota.lease_token],
          );
        }
        const pending = (scenario.includes("dispatch")
          ? dispatch(second)
          : scenario === "refund before binding"
          ? second.queryObject(
            "SELECT * FROM public.reserve_protected_insight_chat_send_with_context($1,$2,$3,'Question',$4,NULL,1,$5,$6)",
            [
              owner,
              crypto.randomUUID(),
              scan,
              request,
              quota!.reservation_id,
              quota!.lease_token,
            ],
          )
          : reserve(second)).then(
            (result) => ({ ok: true as const, result }),
            (error) => ({
              ok: false as const,
              code: error.fields?.code as string,
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
        if (scenario.startsWith("duplicate")) {
          assert(result.ok);
          assertEquals(result.result.rows, [{ result: { status: "held" } }]);
        } else {
          assert(!result.ok);
          assertEquals(
            result.code,
            scenario.startsWith("deletion") ? "P0002" : "55000",
          );
        }
        await second.queryArray(result.ok ? "COMMIT" : "ROLLBACK");
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM internal.insight_chat_execution_fences WHERE scan_id=$1",
            [scan],
          )).rows[0].count,
          scenario.startsWith("deletion") ? 0 : 1,
        );
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
              "UPDATE internal.observation_history_rollout SET chat_context_enabled=$1,chat_execution_enabled=$2",
              [rollout.chat_context_enabled, rollout.chat_execution_enabled],
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
