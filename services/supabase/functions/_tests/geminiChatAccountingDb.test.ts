import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "Gemini protected reply and ordinary message trigger share one receipt ledger event",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const db = new Client(url);
    await db.connect();
    try {
      await db.queryArray("BEGIN");
      await db.queryArray("SET LOCAL request.jwt.claim.role='service_role'");
      const helpers = await Deno.readTextFile(
        new URL(
          "../../tests/insight_chat_execution_fence.sql",
          import.meta.url,
        ),
      );
      await db.queryArray(
        helpers.split("-- BEGIN EXECUTION FENCE HELPERS\n")[1].split(
          "-- END EXECUTION FENCE HELPERS",
        )[0],
      );
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        request = crypto.randomUUID(),
        conversation = crypto.randomUUID();
      await db.queryArray("SELECT pg_temp.seed_fenced_chat($1,$2)", [
        owner,
        scan,
      ]);
      await db.queryArray("SELECT pg_temp.open_fenced_chat()");
      await db.queryArray(
        "UPDATE internal.ai_quota_policies SET model='gemini-3.5-flash-lite',policy_version=policy_version+1 WHERE operation='insight_chat_reply' AND allowed",
      );
      await db.queryArray(
        "INSERT INTO internal.gemini_assignment_revisions SELECT operation,effective_plan,policy_version,model,0 FROM internal.ai_quota_policies WHERE operation='insight_chat_reply' AND allowed",
      );
      await db.queryArray(
        "SELECT public.reserve_protected_insight_chat_quota($1,$2,$3,'Question',NULL,1,repeat('a',64))",
        [owner, scan, request],
      );
      const grant =
        (await db.queryObject<{ reservation_id: string; lease_token: string }>(
          "SELECT reservation_id,lease_token FROM internal.insight_chat_execution_fences WHERE scan_id=$1 AND client_message_id=$2",
          [scan, request],
        )).rows[0];
      await db.queryArray(
        "SELECT public.reserve_protected_insight_chat_send_with_context($1,$2,$3,'Question',$4,NULL,1,$5,$6)",
        [
          owner,
          conversation,
          scan,
          request,
          grant.reservation_id,
          grant.lease_token,
        ],
      );
      await db.queryArray(
        "SELECT public.grant_protected_insight_chat_dispatch($1,$2,$3,$4,$5)",
        [owner, scan, request, grant.reservation_id, grant.lease_token],
      );
      const receipt = (await db.queryObject<{ id: string }>(
        "SELECT public.authorize_gemini_transport($1,$2,$3,1) id",
        [grant.reservation_id, owner, grant.lease_token],
      )).rows[0].id;
      const usage = {
        promptTokens: 10,
        candidateTokens: 5,
        thinkingTokens: 3,
        cachedTokens: 0,
        toolTokens: 0,
        totalTokens: 18,
        modalityBreakdown: {
          prompt: { text: 10 },
          cached: {},
          candidates: { text: 5 },
          tool: {},
        },
      };
      await db.queryArray(
        "SELECT public.record_gemini_invocation_receipt($1,$2,$3)",
        [
          receipt,
          grant.lease_token,
          JSON.stringify({
            returnedModel: "gemini-3.5-flash-lite",
            usage,
            usageConsistent: true,
            finishReason: "STOP",
            failure: null,
          }),
        ],
      );
      const message = (await db.queryObject<{ id: string }>(
        "SELECT message_id id FROM internal.insight_chat_execution_fences WHERE scan_id=$1 AND client_message_id=$2",
        [scan, request],
      )).rows[0].id;
      const reply = {
        answer: "Synthetic answer",
        model: "gemini-3.5-flash-lite",
        is_refusal: false,
        refusal_reason: null,
        usage: {
          prompt_tokens: 10,
          candidate_tokens: 5,
          thinking_tokens: 3,
          cached_tokens: 0,
          total_tokens: 18,
          modality_breakdown: usage.modalityBreakdown,
        },
      };
      await db.queryArray(
        "SELECT public.complete_protected_insight_chat_reply($1,$2,$3,'Question',NULL,1,$4,$5,$6,$7,$8)",
        [
          owner,
          scan,
          request,
          message,
          conversation,
          grant.reservation_id,
          grant.lease_token,
          JSON.stringify(reply),
        ],
      );
      await db.queryArray("SET CONSTRAINTS ALL IMMEDIATE");
      const rows = (await db.queryObject<
        { model: string; returned: string; cost: string; source_type: string }
      >(
        "SELECT model,metadata->>'ai_returned_model' returned,estimated_cost_microusd::text cost,source_type FROM public.ai_usage_events WHERE source_id=$1 OR conversation_id=$2",
        [receipt, conversation],
      )).rows;
      assertEquals(rows.length, 1);
      assertEquals(rows[0].model, "gemini-3.5-flash-lite");
      assertEquals(rows[0].returned, "gemini-3.5-flash-lite");
      assertEquals(rows[0].source_type, "gemini_invocation_receipt");
      assert(Number(rows[0].cost) > 0);
      // The ordinary message insert invokes this same SQL trigger. Re-firing it
      // on the persisted immutable message must not create the legacy event.
      await db.queryArray(
        "UPDATE public.insight_chat_messages SET llm_total_tokens=llm_total_tokens WHERE conversation_id=$1 AND role='assistant'",
        [conversation],
      );
      assertEquals(
        (await db.queryObject<{ n: string }>(
          "SELECT count(*)::text n FROM public.ai_usage_events WHERE source_id=$1 OR conversation_id=$2",
          [receipt, conversation],
        )).rows[0].n,
        "1",
      );
    } finally {
      await db.queryArray("ROLLBACK").catch(() => {});
      await db.end();
    }
  },
});
