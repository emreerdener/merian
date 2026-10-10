import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  admitInsightChatTurnContext,
  InsightChatContextAdmissionError,
  parseInsightChatContextAdmission,
} from "../insight-chat/contextAdmission.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const request = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  conversationId: id(4),
  messageText: "Question",
  displayedTicket: {
    analysis_id: id(5),
    state_revision: 1,
    review_revision: 0,
  },
};
function response() {
  return [{
    conversation_id: id(6),
    is_replay: false,
    sends_today: 1,
    message: {
      id: id(7),
      conversation_id: id(6),
      user_id: id(1),
      scan_id: id(2),
      role: "user",
      client_message_id: id(3),
      message_text: "Question",
      created_at: "2026-10-06T00:00:00.123456+00:00",
      model: null,
      llm_prompt_tokens: null,
      llm_candidate_tokens: null,
      llm_thinking_tokens: null,
      llm_total_tokens: null,
      llm_cached_tokens: null,
      is_refusal: false,
      refusal_reason: null,
      safety_metadata: null,
      llm_usage_metadata: {},
    },
    context_snapshot: {
      context_version: 1,
      source_kind: "analysis_history_v1",
      displayed_ticket: request.displayedTicket,
      scan_context: {
        extracted_visual_traits: [],
        colors: [],
        ecological_interactions: [],
        primary_identification: null,
        confirmed_species_identity: null,
        identification_provenance: null,
        ai_identification_review: null,
        user_observation_context: null,
        pet_identification: null,
        candidates: null,
        species_dictionary: null,
        confirmed_species: null,
      },
      conversation_prefix: [{ role: "assistant", text: "Original" }],
    },
  }];
}
function client(fetcher: typeof fetch) {
  return createClient("https://example.invalid", "synthetic-key", {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: { fetch: fetcher },
  });
}
Deno.test("immutable admission binds returned conversation, message and original ticket in detached data", () => {
  const raw = response();
  const result = parseInsightChatContextAdmission(raw, request);
  assertEquals(result.conversationId, id(6));
  assert(result.conversationId !== request.conversationId);
  assertEquals(result.message.message_text, "Question");
  assertEquals(result.context.displayed_ticket, request.displayedTicket);
  assert(!("model" in result.message));
  assert(Object.isFrozen(result.context));
  raw[0].context_snapshot.conversation_prefix[0].text = "Changed";
  assertEquals(result.context.conversation_prefix[0].text, "Original");
  assertEquals(
    parseInsightChatContextAdmission([{
      ...response()[0],
      is_replay: true,
      sends_today: 20,
    }], request).isReplay,
    true,
  );
});
Deno.test("immutable admission rejects ambiguous cardinality and mismatched turn identity", () => {
  for (
    const value of [
      null,
      {},
      [],
      [...response(), ...response()],
      [{ ...response()[0], extra: true }],
      [{ ...response()[0], sends_today: -1 }],
      [{ ...response()[0], is_replay: 1 }],
    ]
  ) assertThrows(() => parseInsightChatContextAdmission(value, request));
  for (
    const patch of [
      { conversation_id: id(4) },
      { user_id: id(8) },
      { scan_id: id(8) },
      { role: "assistant" },
      { client_message_id: id(8) },
      { message_text: "Changed" },
    ]
  ) {
    assertThrows(() =>
      parseInsightChatContextAdmission([{
        ...response()[0],
        message: { ...response()[0].message, ...patch },
      }], request)
    );
  }
  assertThrows(() =>
    parseInsightChatContextAdmission([{
      ...response()[0],
      context_snapshot: {
        ...response()[0].context_snapshot,
        displayed_ticket: { ...request.displayedTicket, state_revision: 2 },
      },
    }], request)
  );
});
Deno.test("immutable admission sends one original immutable request without transparent retries", async () => {
  const original = structuredClone(request);
  let calls = 0;
  const result = await admitInsightChatTurnContext(
    client((url, init) => {
      calls++;
      assertEquals(
        String(url),
        "https://example.invalid/rest/v1/rpc/reserve_insight_chat_send_with_context",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_user_id: id(1),
        p_scan_id: id(2),
        p_client_message_id: id(3),
        p_conversation_id: id(4),
        p_message_text: "Question",
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
      });
      original.displayedTicket.state_revision = 9;
      assert(init?.signal);
      return Promise.resolve(Response.json(response()));
    }),
    original,
    new AbortController().signal,
  );
  assertEquals(result.context.displayed_ticket, request.displayedTicket);
  assertEquals(calls, 1);
});
Deno.test("immutable admission classifies only exact transactional denials, never raw upstream errors", async () => {
  for (
    const [code, message, outcome] of [
      ["40001", "field_chat_context_conflict", "rejected"],
      ["23505", "field_chat_idempotency_conflict", "rejected"],
      ["55000", "field_chat_context_missing", "rejected"],
      ["P0001", "field_chat_daily_limit_reached", "rejected"],
      ["54000", "field_chat_conversation_limit_reached", "rejected"],
      ["P0002", "field_chat_subject_not_found", "rejected"],
      ["55000", "field_chat_admission_cutover_pending", "rejected"],
      ["42501", "field_chat_access_forbidden", "rejected"],
      ["22023", "field_chat_invalid_request", "rejected"],
      ["PGRST202", "field_chat_context_missing", "unknown"],
      ["40001", "private diagnostic", "unknown"],
      ["55000", "prefix field_chat_context_missing", "unknown"],
    ] as const
  ) {
    let calls = 0;
    const error = await assertRejects(
      () =>
        admitInsightChatTurnContext(
          client(() => {
            calls++;
            return Promise.resolve(
              Response.json({ code, message }, { status: 400 }),
            );
          }),
          request,
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, outcome);
    assertEquals(
      error.code,
      outcome === "rejected" ? message : "field_chat_context_unavailable",
    );
    assertEquals(calls, 1);
  }
});
Deno.test("lost replies, malformed success, throttling and server failures hold unknown without retry", async () => {
  for (
    const fetcher of [
      () => Promise.reject(new Error("private transport")),
      () => Promise.resolve(Response.json([])),
      () =>
        Promise.resolve(
          Response.json(response().map((r) => ({ ...r, private: "unknown" }))),
        ),
      ...[429, 503, 520].map((status) => () =>
        Promise.resolve(
          Response.json({ message: "private" }, {
            status,
            headers: { "Retry-After": "0" },
          }),
        )
      ),
    ]
  ) {
    let calls = 0;
    const error = await assertRejects(
      () =>
        admitInsightChatTurnContext(
          client(() => {
            calls++;
            return fetcher();
          }),
          request,
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, "unknown");
    assertEquals(error.message, "field_chat_context_unavailable");
    assertEquals(calls, 1);
  }
});
Deno.test("cancellation before I/O is inert but cancellation after dispatch remains uncertain", async () => {
  const pre = new AbortController();
  pre.abort();
  let calls = 0;
  const fake = client(() => {
    calls++;
    return Promise.resolve(Response.json(response()));
  });
  await assertRejects(() =>
    admitInsightChatTurnContext(fake, request, pre.signal)
  );
  assertEquals(calls, 0);
  const during = new AbortController();
  const error = await assertRejects(
    () =>
      admitInsightChatTurnContext(
        client(() => {
          during.abort();
          return Promise.resolve(Response.json(response()));
        }),
        request,
        during.signal,
      ),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "unknown");
  await assertRejects(() =>
    admitInsightChatTurnContext(
      fake,
      { ...request, conversationId: "invalid" },
      new AbortController().signal,
    )
  );
  assertEquals(calls, 0);
});

Deno.test("admission projects no unrelated message metadata or future table columns", () => {
  const raw = response()[0];
  const value = parseInsightChatContextAdmission([{
    ...raw,
    message: {
      ...raw.message,
      private_column: { secret: "private" },
      llm_usage_metadata: { other: "private" },
    },
  }], request);
  assertEquals(
    Object.keys(value.message).sort(),
    [
      "id",
      "conversation_id",
      "user_id",
      "scan_id",
      "role",
      "client_message_id",
      "message_text",
    ].sort(),
  );
  assert(!JSON.stringify(value).includes("private"));
});
