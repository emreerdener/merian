import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { parseChatContextTicket } from "../insight-chat/storedContextContract.ts";
import { parsePreparedInsightChatContext } from "../insight-chat/preparedContext.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function waitBlocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const rows = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (rows.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected chat context serialization not observed");
}
for (
  const scenario of [
    "authority after preflight",
    "preflight during authority",
    "admission first",
    "deletion after preflight",
  ]
) {
  Deno.test({
    name: `Immutable Insight preflight DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const [observer, first, second] = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        request = crypto.randomUUID();
      let rollout: Record<string, unknown> | undefined,
        cutover: Record<string, unknown> | undefined;
      try {
        for (const client of [observer, first, second]) await client.connect();
        const sql = await Deno.readTextFile(
          new URL("../../tests/insight_chat_turn_context.sql", import.meta.url),
        );
        await observer.queryArray(
          sql.split("-- BEGIN CHAT CONTEXT HELPERS\n")[1].split(
            "-- END CHAT CONTEXT HELPERS",
          )[0],
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_chat_observation($1,$2)",
          [owner, scan],
        );
        rollout = (await observer.queryObject<{ row: Record<string, unknown> }>(
          "SELECT to_jsonb(r) AS row FROM internal.observation_history_rollout r",
        )).rows[0].row;
        cutover = (await observer.queryObject<{ row: Record<string, unknown> }>(
          "SELECT to_jsonb(c) AS row FROM internal.field_chat_admission_cutover c",
        )).rows[0].row;
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
        );
        await observer.queryArray("SELECT pg_temp.open_chat_fixture()");
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ role: "authenticated", sub: owner })],
        );
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [scan],
        );
        const ticket = (await observer.queryObject<{ ticket: unknown }>(
          "SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) AS ticket FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id WHERE h.observation_id=$1",
          [scan],
        )).rows[0].ticket;
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
        );
        const preflight = (client: Client) =>
          client.queryObject<{ prepared: unknown }>(
            "SELECT public.prepare_insight_chat_send_context($1,$2,$3,1) AS prepared",
            [owner, scan, JSON.stringify(ticket)],
          );
        const frozen = parsePreparedInsightChatContext(
          (await preflight(observer)).rows[0].prepared,
          {
            ownerId: owner,
            scanId: scan,
            displayedTicket: parseChatContextTicket(ticket),
          },
        );
        assertEquals(frozen.displayed_ticket, ticket);
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',TRUE)",
          );
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const admit = (client: Client) =>
          client.queryObject<
            { context_snapshot: Record<string, unknown>; is_replay: boolean }
          >(
            "SELECT * FROM public.reserve_insight_chat_send_with_context($1,$2,$3,'Question',$4,$5,1)",
            [owner, crypto.randomUUID(), scan, request, JSON.stringify(ticket)],
          );
        let original: Record<string, unknown> | undefined;
        if (scenario === "admission first") {
          original = (await admit(first)).rows[0].context_snapshot;
        } else {
          await first.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          if (scenario === "deletion after preflight") {
            await first.queryArray("DELETE FROM public.scans WHERE id=$1", [
              scan,
            ]);
          } else {await first.queryArray(
              "UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=$1",
              [scan],
            );}
        }
        const pending = (scenario === "admission first"
          ? (async () => {
            await second.queryArray(
              "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
              [owner],
            );
            await second.queryArray(
              "UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=$1",
              [scan],
            );
            return null;
          })()
          : scenario === "preflight during authority"
          ? preflight(second)
          : admit(second)).then(
            (value) => ({ ok: true as const, value }),
            (error) => ({
              ok: false as const,
              code: error.fields?.code,
              message: error.message,
            }),
          );
        await waitBlocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        const result = await pending;
        if (scenario === "admission first") assert(result.ok);
        else {
          assert(!result.ok);
          assertEquals(
            result.code,
            scenario === "deletion after preflight" ? "P0002" : "40001",
          );
          assertEquals(
            result.message,
            scenario === "deletion after preflight"
              ? "field_chat_subject_not_found"
              : "field_chat_context_conflict",
          );
        }
        await second.queryArray(result.ok ? "COMMIT" : "ROLLBACK");
        const contexts = await observer.queryObject<{ count: number }>(
          "SELECT count(*)::int AS count FROM internal.insight_chat_turn_contexts c JOIN public.insight_chat_messages m ON m.id=c.message_id WHERE m.user_id=$1",
          [owner],
        );
        assertEquals(contexts.rows[0].count, original ? 1 : 0);
        const slots = await observer.queryObject<{ count: number }>(
          "SELECT COALESCE(sum(admitted_count),0)::int AS count FROM internal.field_chat_daily_admissions WHERE user_id=$1",
          [owner],
        );
        assertEquals(slots.rows[0].count, original ? 1 : 0);

        if (scenario === "admission first") {
          await observer.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
          );
          assertEquals(
            (await admit(observer)).rows[0].context_snapshot,
            original,
          );
        }
      } finally {
        for (const client of [first, second]) {
          try {
            await client.queryArray("ROLLBACK");
          } catch { /* closed setup */ }
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
              "UPDATE internal.observation_history_rollout SET chat_context_enabled=$1,reader_enabled=$2,enrollment_enabled=$3,saved_import_enabled=$4",
              [
                rollout.chat_context_enabled,
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
        } finally {
          for (const client of [observer, first, second]) await client.end();
        }
      }
    },
  });
}
