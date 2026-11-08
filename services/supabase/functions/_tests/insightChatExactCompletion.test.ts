import { assert, assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import { InsightChatContextAdmissionError } from "../insight-chat/contextAdmission.ts";
import {
  admitInsightChatLocalRefusal,
  LOCAL_REFUSAL_REASONS,
  parseInsightChatCompletion,
  readInsightChatCompletion,
} from "../insight-chat/exactCompletion.ts";
import { refusalAnswer } from "../insight-chat/guards.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const request = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  messageText: "Question",
  displayedTicket: null,
  messageId: id(4),
  conversationId: id(5),
};
const local = {
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  messageText: "Question",
  displayedTicket: null,
  conversationId: id(5),
  reason: "dangerous_handling" as const,
};
async function response() {
  return {
    context_version: 1,
    completed: true,
    message: {
      id: await deriveFieldChatAssistantMessageId(id(5), id(3)),
      conversation_id: id(5),
      scan_id: id(2),
      role: "assistant",
      text: refusalAnswer("dangerous_handling"),
      client_message_id: id(3),
      model: null,
      is_refusal: true,
      refusal_reason: "dangerous_handling",
      created_at: "2026-10-06T12:00:00+00:00",
    },
  };
}
Deno.test("exact completion returns only frozen bounded owned receipt", async () => {
  const raw = await response();
  const result = await parseInsightChatCompletion(raw, request, id(5));
  assert(result.completed);
  assert(Object.isFrozen(result.message));
  raw.message.text = "Changed";
  assertEquals(result.message.text, refusalAnswer("dangerous_handling"));
  assertEquals(
    await parseInsightChatCompletion(
      { context_version: 1, completed: false },
      request,
      id(5),
    ),
    { completed: false },
  );
});
Deno.test("exact completion rejects wrong identity, additive fields and invalid values", async () => {
  const raw = await response();
  for (
    const patch of [
      { id: id(10) },
      { conversation_id: id(6) },
      { scan_id: id(9) },
      { client_message_id: id(9) },
      { role: "user" },
      { text: "" },
      { text: "x".repeat(4001) },
      { model: "x".repeat(201) },
      { is_refusal: "true" },
      { created_at: "infinity" },
      { created_at: "yesterday" },
      { safety_metadata: { request_id: id(3) } },
    ]
  ) {
    await assertRejects(() =>
      parseInsightChatCompletion(
        { ...raw, message: { ...raw.message, ...patch } },
        request,
        id(5),
      )
    );
  }
  for (
    const malformed of [
      null,
      {},
      [],
      { context_version: 2, completed: false },
      { context_version: 1, completed: false, message: {} },
      { ...raw, context_snapshot: {} },
    ]
  ) {
    await assertRejects(() =>
      parseInsightChatCompletion(malformed, request, id(5))
    );
  }
});
Deno.test("completion fixed RPC binds original context tuple with one no-retry call", async () => {
  let calls = 0;
  const raw = await response();
  const client = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: (input, init) => {
        calls++;
        assert(String(input).endsWith("/rpc/get_insight_chat_turn_completion"));
        assertEquals(JSON.parse(String(init?.body)), {
          p_user_id: id(1),
          p_scan_id: id(2),
          p_client_message_id: id(3),
          p_message_text: "Question",
          p_displayed_ticket: null,
          p_context_version: 1,
          p_message_id: id(4),
          p_conversation_id: id(5),
        });
        return Promise.resolve(Response.json(raw));
      },
    },
  });
  assert(
    (await readInsightChatCompletion(
      client,
      request,
      new AbortController().signal,
    )).completed,
  );
  assertEquals(calls, 1);
});
Deno.test("local refusal accepts exact static response only and freezes request before await", async () => {
  let calls = 0;
  const raw = await response();
  const mutable = { ...local };
  const client = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: (input, init) => {
        calls++;
        assert(String(input).endsWith("/rpc/admit_insight_chat_local_refusal"));
        const body = JSON.parse(String(init?.body));
        assertEquals(Object.keys(body).length, 8);
        assertEquals(body.p_refusal_reason, "dangerous_handling");
        mutable.scanId = id(9);
        return Promise.resolve(Response.json(raw));
      },
    },
  });
  const result = await admitInsightChatLocalRefusal(
    client,
    mutable,
    new AbortController().signal,
  );
  assertEquals(result.message.scan_id, id(2));
  assertEquals(calls, 1);
});
Deno.test("local refusal rejects incomplete, changed copy and provider metadata", async () => {
  const raw = await response();
  for (
    const data of [
      { context_version: 1, completed: false },
      { ...raw, message: { ...raw.message, text: "Other" } },
      { ...raw, message: { ...raw.message, model: "provider" } },
      {
        ...raw,
        message: { ...raw.message, refusal_reason: "medical_or_veterinary" },
      },
      { ...raw, message: { ...raw.message, is_refusal: false } },
    ]
  ) {
    let calls = 0;
    const client = createClient("https://example.invalid", "synthetic-key", {
      global: {
        fetch: () => {
          calls++;
          return Promise.resolve(Response.json(data));
        },
      },
    });
    const error = await assertRejects(
      () =>
        admitInsightChatLocalRefusal(
          client,
          local,
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.transactionOutcome, "unknown");
    assertEquals(calls, 1);
  }
});
Deno.test("uncertain refusal errors never repeat writes or leak diagnostics", async () => {
  for (const result of ["network", "http", "malformed"]) {
    let calls = 0;
    const client = createClient("https://example.invalid", "synthetic-key", {
      global: {
        fetch: () => {
          calls++;
          if (result === "network") {
            return Promise.reject(new Error("private diagnostic"));
          }
          return Promise.resolve(
            result === "http"
              ? new Response("private diagnostic", { status: 503 })
              : Response.json({}),
          );
        },
      },
    });
    const error = await assertRejects(
      () =>
        admitInsightChatLocalRefusal(
          client,
          local,
          new AbortController().signal,
        ),
      InsightChatContextAdmissionError,
    );
    assertEquals(error.message, "field_chat_completion_unavailable");
    assertEquals(error.transactionOutcome, "unknown");
    assertEquals(calls, 1);
  }
});
Deno.test("known refusal denial describes only this transaction", async () => {
  const client = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: () =>
        Promise.resolve(
          Response.json({
            code: "55000",
            message: "field_chat_completion_held",
          }, { status: 400 }),
        ),
    },
  });
  const error = await assertRejects(
    () =>
      admitInsightChatLocalRefusal(client, local, new AbortController().signal),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "rejected");
});
Deno.test("preabort sends nothing, post-dispatch abort keeps refusal unknown", async () => {
  const before = new AbortController();
  before.abort();
  let calls = 0;
  const after = new AbortController();
  const raw = await response();
  const client = createClient("https://example.invalid", "synthetic-key", {
    global: {
      fetch: () => {
        calls++;
        after.abort();
        return Promise.resolve(Response.json(raw));
      },
    },
  });
  await assertRejects(() =>
    admitInsightChatLocalRefusal(client, local, before.signal)
  );
  assertEquals(calls, 0);
  const error = await assertRejects(
    () => admitInsightChatLocalRefusal(client, local, after.signal),
    InsightChatContextAdmissionError,
  );
  assertEquals(error.transactionOutcome, "unknown");
  assertEquals(calls, 1);
});
Deno.test("SQL closed local refusal copy matches existing TypeScript policy", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261006124159_prepare_insight_chat_exact_completion.sql",
      import.meta.url,
    ),
  );
  const matches = [...sql.matchAll(/WHEN '([a-z_]+)' THEN RETURN '([^']+)';/g)];
  assertEquals(matches.map((x) => x[1]), [...LOCAL_REFUSAL_REASONS]);
  for (const [, reason, text] of matches) {
    assertEquals(text, refusalAnswer(reason));
  }
});
