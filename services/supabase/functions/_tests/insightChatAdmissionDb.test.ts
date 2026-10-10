import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { parseInsightChatContextAdmission } from "../insight-chat/contextAdmission.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "immutable admission decodes real fresh and replay rows without adopting a proposed conversation",
  ignore: !databaseUrl,
  async fn() {
    assert(databaseUrl);
    assert(
      ["127.0.0.1", "localhost", "[::1]"].includes(
        new URL(databaseUrl).hostname,
      ),
    );
    const db = new Client(databaseUrl);
    try {
      await db.connect();
      await db.queryArray("BEGIN");
      const source = await Deno.readTextFile(
        new URL("../../tests/insight_chat_turn_context.sql", import.meta.url),
      );
      await db.queryArray(
        source.split("-- BEGIN CHAT CONTEXT HELPERS\n")[1].split(
          "-- END CHAT CONTEXT HELPERS",
        )[0],
      );
      const request = {
        ownerId: crypto.randomUUID(),
        scanId: crypto.randomUUID(),
        conversationId: crypto.randomUUID(),
        clientMessageId: crypto.randomUUID(),
        messageText: "Question",
        displayedTicket: null,
      };
      await db.queryArray("SELECT pg_temp.seed_chat_observation($1,$2)", [
        request.ownerId,
        request.scanId,
      ]);
      await db.queryArray(
        "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',TRUE)",
      );
      await db.queryArray("SELECT pg_temp.open_chat_fixture()");
      const rows = await db.queryObject(
        "SELECT * FROM public.reserve_insight_chat_send_with_context($1,$2,$3,$4,$5,NULL,1)",
        [
          request.ownerId,
          request.conversationId,
          request.scanId,
          request.messageText,
          request.clientMessageId,
        ],
      );
      const first = parseInsightChatContextAdmission(rows.rows, request);
      assertEquals(first.isReplay, false);
      assertEquals(first.sendsToday, 1);
      assertEquals(first.message.message_text, "Question");
      await db.queryArray(
        "UPDATE internal.observation_history_rollout SET chat_context_enabled=FALSE",
      );
      await db.queryArray(
        "UPDATE public.scans SET ai_reasoning='Changed later' WHERE id=$1",
        [request.scanId],
      );
      const retry = { ...request, conversationId: crypto.randomUUID() };
      const replayRows = await db.queryObject(
        "SELECT * FROM public.reserve_insight_chat_send_with_context($1,$2,$3,$4,$5,NULL,1)",
        [
          retry.ownerId,
          retry.conversationId,
          retry.scanId,
          retry.messageText,
          retry.clientMessageId,
        ],
      );
      const replay = parseInsightChatContextAdmission(replayRows.rows, retry);
      assertEquals(replay.isReplay, true);
      assertEquals(replay.conversationId, first.conversationId);
      assertEquals(replay.context, first.context);
      assertEquals(replay.sendsToday, 1);
    } finally {
      await db.queryArray("ROLLBACK").catch(() => {});
      await db.end();
    }
  },
});
