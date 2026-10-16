import { assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { admitOrRecoverInsightChatContext } from "../insight-chat/contextAdmissionRecovery.ts";
import { InsightChatContextAdmissionError } from "../insight-chat/contextAdmission.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  conversationId: id(4),
  messageText: "Question",
  displayedTicket: null,
};
const stored = {
  context_version: 1,
  found: true,
  message: {
    id: id(5),
    conversation_id: id(6),
    scan_id: id(2),
    user_id: id(1),
    role: "user",
    client_message_id: id(3),
    message_text: "Question",
  },
  context_snapshot: {
    context_version: 1,
    source_kind: "legacy_scan_v1",
    displayed_ticket: null,
    scan_context: {
      primary_identification: null,
      identification_provenance: null,
      confirmed_species_identity: null,
      ai_identification_review: null,
      pet_identification: null,
      user_observation_context: null,
      candidates: null,
      extracted_visual_traits: [],
      colors: [],
      ecological_interactions: [],
      species_dictionary: null,
      confirmed_species: null,
    },
    conversation_prefix: [],
  },
};
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
Deno.test("lost admission reply recovers exact original tuple without second write or fabricated receipt", async () => {
  const calls: string[] = [];
  const mutable = { ...input };
  const result = await admitOrRecoverInsightChatContext(
    client((url, init) => {
      calls.push(String(url).split("/").at(-1)!);
      if (calls.length === 1) {
        mutable.messageText = "Changed";
        return Promise.reject(new Error("lost reply"));
      }
      assertEquals(JSON.parse(String(init?.body)), {
        p_user_id: input.ownerId,
        p_scan_id: input.scanId,
        p_client_message_id: input.clientMessageId,
        p_message_text: "Question",
        p_displayed_ticket: null,
        p_context_version: 1,
      });
      return Promise.resolve(Response.json(stored));
    }),
    mutable,
    new AbortController().signal,
  );
  assertEquals(calls, [
    "reserve_insight_chat_send_with_context",
    "get_insight_chat_turn_context",
  ]);
  assertEquals(result.kind, "recovered");
  if (result.kind === "recovered") {
    assertEquals(result.recovered.message.conversation_id, id(6));
  }
});
Deno.test("an absent or failed recovery after uncertain admission never authorizes a second attempt", async () => {
  for (
    const recovery of [
      () =>
        Promise.resolve(Response.json({ context_version: 1, found: false })),
      () => Promise.reject(new Error("private")),
      () =>
        Promise.resolve(
          Response.json({
            code: "P0002",
            message: "field_chat_subject_not_found",
          }, { status: 404 }),
        ),
      () =>
        Promise.resolve(
          Response.json({
            code: "23505",
            message: "field_chat_idempotency_conflict",
          }, { status: 409 }),
        ),
      () =>
        Promise.resolve(Response.json({ context_version: 2, found: false })),
    ]
  ) {
    let calls = 0;
    const error = await assertRejects(
      () =>
        admitOrRecoverInsightChatContext(
          client(() => {
            calls++;
            return calls === 1 ? Promise.reject(new Error("lost")) : recovery();
          }),
          input,
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, "unknown");
    assertEquals(error.code, "field_chat_context_unavailable");
    assertEquals(calls, 2);
  }
});
Deno.test("conclusive rejection and cancellation do not start a new recovery or write", async () => {
  let calls = 0;
  const error = await assertRejects(
    () =>
      admitOrRecoverInsightChatContext(
        client(() => {
          calls++;
          return Promise.resolve(
            Response.json({
              code: "23505",
              message: "field_chat_idempotency_conflict",
            }, { status: 409 }),
          );
        }),
        input,
        new AbortController().signal,
      ),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "rejected");
  assertEquals(calls, 1);
  const cancellation = new AbortController();
  calls = 0;
  const uncertain = await assertRejects(
    () =>
      admitOrRecoverInsightChatContext(
        client(() => {
          calls++;
          cancellation.abort();
          return Promise.reject(new Error("cancelled"));
        }),
        input,
        cancellation.signal,
      ),
    InsightChatContextAdmissionError,
  );
  assertEquals(uncertain.transactionOutcome, "unknown");
  assertEquals(calls, 1);
});
