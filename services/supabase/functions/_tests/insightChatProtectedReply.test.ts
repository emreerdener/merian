import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import {
  completeOrRecoverProtectedChatReply,
  completeProtectedChatReply,
  parseProtectedChatReply,
} from "../insight-chat/protectedReply.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const payload = () => ({
  answer: "Synthetic answer",
  model: "gemini-2.5-flash",
  is_refusal: false,
  refusal_reason: null,
  usage: {
    prompt_tokens: 10,
    candidate_tokens: 5,
    thinking_tokens: 0,
    total_tokens: 15,
    cached_tokens: 0,
    modality_breakdown: {
      prompt: { text: 10 },
      cached: {},
      candidates: { text: 5 },
      tool: {},
    },
  },
});
const request = () => ({
  ownerId: id(1),
  scanId: id(2),
  clientMessageId: id(3),
  messageText: "Question",
  displayedTicket: null,
  messageId: id(4),
  conversationId: id(5),
  reservationId: id(6),
  leaseToken: id(7),
  reply: parseProtectedChatReply(payload()),
});
async function receipt() {
  return {
    context_version: 1,
    completed: true,
    message: {
      id: await deriveFieldChatAssistantMessageId(id(5), id(3)),
      conversation_id: id(5),
      scan_id: id(2),
      role: "assistant",
      text: "Synthetic answer",
      client_message_id: id(3),
      model: "gemini-2.5-flash",
      is_refusal: false,
      refusal_reason: null,
      created_at: "2026-10-06T12:00:00Z",
    },
  };
}
function client(fetch: typeof globalThis.fetch) {
  return createClient("https://example.invalid", "synthetic-key", {
    global: { fetch },
  });
}
Deno.test("protected reply closes usage and immutable payload", () => {
  const raw = payload();
  const parsed = parseProtectedChatReply(raw);
  raw.usage.prompt_tokens = 99;
  assertEquals(parsed.usage?.prompt_tokens, 10);
  assert(Object.isFrozen(parsed.usage?.modality_breakdown));
  for (
    const bad of [
      { ...payload(), debug: {} },
      { ...payload(), model: "unknown" },
      { ...payload(), answer: " " },
      { ...payload(), refusal_reason: "reason" },
      { ...payload(), usage: { ...payload().usage, prompt_tokens: -1 } },
      { ...payload(), usage: { ...payload().usage, total_tokens: 2147483648 } },
      { ...payload(), usage: { ...payload().usage, total_tokens: 1.5 } },
      {
        ...payload(),
        usage: {
          ...payload().usage,
          modality_breakdown: {
            ...payload().usage.modality_breakdown,
            prompt: { raw: 1 },
          },
        },
      },
    ]
  ) assertThrows(() => parseProtectedChatReply(bad));
  assertEquals(
    parseProtectedChatReply({ ...payload(), usage: null }).usage,
    null,
  );
});
Deno.test("protected reply sends exact original grant once", async () => {
  const raw = await receipt();
  let calls = 0;
  const input = request();
  const db = client((_url, init) => {
    calls++;
    assert(String(_url).endsWith("/rpc/complete_protected_insight_chat_reply"));
    assertEquals(JSON.parse(String(init?.body)), {
      p_user_id: id(1),
      p_scan_id: id(2),
      p_client_message_id: id(3),
      p_message_text: "Question",
      p_displayed_ticket: null,
      p_context_version: 1,
      p_message_id: id(4),
      p_conversation_id: id(5),
      p_reservation_id: id(6),
      p_lease_token: id(7),
      p_reply: payload(),
    });
    return Promise.resolve(Response.json(raw));
  });
  assert(
    (await completeProtectedChatReply(db, input, new AbortController().signal))
      .completed,
  );
  assertEquals(calls, 1);
});
Deno.test("unknown write reads same full payload once despite caller mutation", async () => {
  const raw = await receipt();
  const input = request();
  const paths: string[] = [];
  const bodies: unknown[] = [];
  const db = client((url, init) => {
    paths.push(String(url).split("/").at(-1)!);
    bodies.push(JSON.parse(String(init?.body)));
    if (paths.length === 1) {
      input.scanId = id(99);
      input.reply = parseProtectedChatReply({
        ...payload(),
        answer: "Changed",
      });
      return Promise.resolve(
        Response.json({ message: "unknown" }, { status: 503 }),
      );
    }
    return Promise.resolve(Response.json(raw));
  });
  assertEquals(
    (await completeOrRecoverProtectedChatReply(
      db,
      input,
      new AbortController().signal,
    )).kind,
    "recovered",
  );
  assertEquals(paths, [
    "complete_protected_insight_chat_reply",
    "get_protected_insight_chat_reply",
  ]);
  assertEquals(bodies[0], bodies[1]);
});
Deno.test("conclusive conflict never retries or reads", async () => {
  let calls = 0;
  const db = client(() => {
    calls++;
    return Promise.resolve(
      Response.json({ code: "23505", message: "field_chat_reply_conflict" }, {
        status: 409,
      }),
    );
  });
  await assertRejects(() =>
    completeOrRecoverProtectedChatReply(
      db,
      request(),
      new AbortController().signal,
    )
  );
  assertEquals(calls, 1);
});
Deno.test("unknown write with absent or conflicting private recovery stays unknown", async () => {
  for (
    const result of [{ context_version: 1, completed: false }, {
      code: "23505",
      message: "field_chat_reply_conflict",
    }]
  ) {
    let calls = 0;
    const db = client(() => {
      calls++;
      return Promise.resolve(
        calls === 1
          ? Response.json({ message: "unknown" }, { status: 503 })
          : Response.json(result, { status: "code" in result ? 409 : 200 }),
      );
    });
    const error = await assertRejects(() =>
      completeOrRecoverProtectedChatReply(
        db,
        request(),
        new AbortController().signal,
      )
    );
    assertEquals(
      (error as { transactionOutcome: string }).transactionOutcome,
      "unknown",
    );
    assertEquals(calls, 2);
  }
});
Deno.test("cancelled reply makes no transport call", async () => {
  let calls = 0;
  const db = client(() => {
    calls++;
    throw new Error("unexpected");
  });
  const controller = new AbortController();
  controller.abort();
  await assertRejects(() =>
    completeOrRecoverProtectedChatReply(db, request(), controller.signal)
  );
  assertEquals(calls, 0);
});
