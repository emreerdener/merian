import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import {
  type ChatNoAdmissionProof,
  parseChatNoAdmission,
  readChatNoAdmission,
  sealChatNoAdmission,
} from "../insight-chat/noAdmission.ts";
import {
  parseProtectedChatSend,
  protectedChatSendPayload,
} from "../insight-chat/protectedSendContract.ts";
import { StoredInsightChatRecoveryError } from "../insight-chat/storedContextRepository.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const saved = () =>
  parseProtectedChatSend(id(1), {
    action: "send",
    context_version: 1,
    scan_id: id(2),
    conversation_id: id(3),
    client_message_id: id(4),
    message_text: "Original question",
    displayed_ticket: {
      analysis_id: id(5),
      state_revision: 4,
      review_revision: 0,
    },
  });
const proof = () => ({
  status: "not_admitted" as const,
  context_version: 1 as const,
  scan_id: id(2),
  conversation_id: id(3),
  client_message_id: id(4),
  reason: "displayed_identification_changed" as const,
});
Deno.test("no-admission proof is closed and bound to every original correlation ID", () => {
  assertEquals(parseChatNoAdmission(proof(), saved()), proof());
  for (
    const changes of [
      { scan_id: id(9) },
      { conversation_id: id(9) },
      { client_message_id: id(9) },
      { reason: "unknown" },
      { context_version: true },
      { context_version: 2 },
      { status: "complete" },
      { message: {} },
      { refund: true },
    ]
  ) {
    assertThrows(() =>
      parseChatNoAdmission({ ...proof(), ...changes }, saved())
    );
  }
  for (
    const value of [null, [], { status: "held", reason: "anything" }, {
      status: "fresh_candidate",
      found: false,
    }, { status: "absent" }]
  ) {
    assertThrows(() => parseChatNoAdmission(value, saved()));
  }
});
Deno.test("fixed proof boundaries send exact immutable tuple once and preserve original input across await", async () => {
  for (
    const [operation, call] of [[
      "get_insight_chat_no_admission",
      readChatNoAdmission,
    ], ["seal_unadmitted_insight_chat_request", sealChatNoAdmission]] as const
  ) {
    let calls = 0;
    const db = createClient("https://example.invalid", "synthetic", {
      global: {
        fetch: (url, init) => {
          calls++;
          assertEquals(String(url).split("/").at(-1), operation);
          assertEquals(JSON.parse(String(init?.body)), {
            p_user_id: id(1),
            p_scan_id: id(2),
            p_conversation_id: id(3),
            p_client_message_id: id(4),
            p_message_text: "Original question",
            p_displayed_ticket: saved().turn.displayedTicket,
            p_context_version: 1,
          });
          return Promise.resolve(Response.json(proof()));
        },
      },
    });
    assertEquals(
      await call(db, saved(), new AbortController().signal),
      proof(),
    );
    assertEquals(calls, 1);
  }
});
Deno.test("unknown or malformed proof response fails closed without retry or proof synthesis", async () => {
  for (
    const response of [
      Response.json({ message: "private" }, { status: 503 }),
      Response.json({ status: "absent" }),
      Response.json({ ...proof(), scan_id: id(9) }),
    ]
  ) {
    let calls = 0;
    const db = createClient("https://example.invalid", "synthetic", {
      global: {
        fetch: () => {
          calls++;
          return Promise.resolve(response);
        },
      },
    });
    await assertRejects(
      () => readChatNoAdmission(db, saved(), new AbortController().signal),
      StoredInsightChatRecoveryError,
      "field_chat_context_unavailable",
    );
    assertEquals(calls, 1);
  }
});
Deno.test("only read recovery may report fresh_candidate; sealing cannot authorize fresh work", async () => {
  const db = createClient("https://example.invalid", "synthetic", {
    global: {
      fetch: () =>
        Promise.resolve(Response.json({ status: "fresh_candidate" })),
    },
  });
  assertEquals(
    await readChatNoAdmission(db, saved(), new AbortController().signal),
    { status: "fresh_candidate" },
  );
  await assertRejects(
    () => sealChatNoAdmission(db, saved(), new AbortController().signal),
    StoredInsightChatRecoveryError,
  );
});
Deno.test("cancelled proof boundary sends no bytes", async () => {
  let calls = 0;
  const db = createClient("https://example.invalid", "synthetic", {
    global: {
      fetch: () => {
        calls++;
        return Promise.resolve(Response.json(proof()));
      },
    },
  });
  await assertRejects(() =>
    readChatNoAdmission(db, saved(), AbortSignal.abort())
  );
  assertEquals(calls, 0);
});

Deno.test("HTTP proof projection rejects held and extra-field internal values", () => {
  for (
    const raw of [{ status: "held" }, { ...proof(), extra: true }, {
      ...proof(),
      reason: "other",
    }]
  ) {
    assertThrows(() =>
      protectedChatSendPayload(raw as unknown as ChatNoAdmissionProof)
    );
  }
});
