import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { parseStoredInsightChatResolution } from "../insight-chat/storedContext.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    if (
      (await observer.queryObject<{ blocked: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
        [blocker, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Recovery serialization not observed");
}
for (
  const scenario of ["admission first", "deletion first", "recovery first"]
) {
  Deno.test({
    name: `Insight context recovery DB concurrency - ${scenario}`,
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
        requestId = crypto.randomUUID(),
        conversation = crypto.randomUUID();
      const request = {
        ownerId: owner,
        scanId: scan,
        clientMessageId: requestId,
        messageText: "Question",
        displayedTicket: null,
      };
      let rollout: Record<string, unknown> | undefined,
        cutover: Record<string, unknown> | undefined;
      try {
        for (const client of [observer, first, second]) await client.connect();
        const helpers = (await Deno.readTextFile(
          new URL(
            "../../tests/insight_chat_turn_context.sql",
            import.meta.url,
          ),
        )).split("-- BEGIN CHAT CONTEXT HELPERS\n")[1].split(
          "-- END CHAT CONTEXT HELPERS",
        )[0];
        await observer.queryArray(helpers);
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
        const insert = (client: Client) =>
          client.queryArray(
            "SELECT * FROM public.reserve_insight_chat_send_with_context($1,$2,$3,'Question',$4,'null',1)",
            [owner, conversation, scan, requestId],
          );
        const recover = (client: Client) =>
          client.queryObject<{ result: unknown }>(
            "SELECT public.get_insight_chat_turn_context($1,$2,$3,'Question',NULL,1) AS result",
            [owner, scan, requestId],
          );
        if (scenario !== "admission first") await insert(observer);
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',TRUE)",
          );
        }
        const firstPid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const secondPid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        let saved: unknown;
        if (scenario === "recovery first") {
          saved = (await recover(first)).rows[0].result;
        } else {
          await first.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          if (scenario === "admission first") await insert(first);
          else {await first.queryArray("DELETE FROM public.scans WHERE id=$1", [
              scan,
            ]);}
        }
        const pending = (scenario === "recovery first"
          ? (async () => {
            await second.queryArray(
              "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
              [owner],
            );
            await second.queryArray("DELETE FROM public.scans WHERE id=$1", [
              scan,
            ]);
            return null;
          })()
          : recover(second)).then(
            (value) => ({ ok: true as const, value }),
            (error) => ({
              ok: false as const,
              code: error.fields?.code,
              message: error.message,
            }),
          );
        await blocked(observer, secondPid, firstPid);
        await first.queryArray("COMMIT");
        const result = await pending;
        if (scenario === "deletion first") {
          assert(!result.ok);
          assertEquals(result.code, "P0002");
          assertEquals(result.message, "field_chat_subject_not_found");
        } else {
          assert(result.ok);
          const decoded = parseStoredInsightChatResolution(
            scenario === "recovery first"
              ? saved
              : result.value?.rows[0].result,
            request,
          );
          assert(decoded.found);
          assertEquals(
            decoded.context.scan_context.ai_reasoning,
            "Original reasoning",
          );
        }
        await second.queryArray(result.ok ? "COMMIT" : "ROLLBACK");
        assertEquals(
          (await observer.queryObject<{ count: number }>(
            "SELECT admitted_count AS count FROM internal.field_chat_daily_admissions WHERE user_id=$1",
            [owner],
          )).rows[0].count,
          1,
        );
      } finally {
        for (const client of [first, second]) {
          try {
            await client.queryArray("ROLLBACK");
          } catch { /*setup failure*/ }
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
          for (const client of [first, second, observer]) await client.end();
        }
      }
    },
  });
}
