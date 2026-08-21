import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import { PublicHttpError } from "./http.ts";
import {
  recoverStaleFieldChatQuota,
  reserveFieldChatSend,
} from "./fieldChatReservation.ts";

const USER_ID = "019fac20-20e3-7f2e-b104-35d3b04a2b03";
const SUBJECT_ID = "019fac20-2370-7911-8bb2-a136ce1ca9c7";
const CONVERSATION_ID = "019fac20-2667-711c-a1a2-97f8b6c6bfb6";
const REQUEST_ID = "019fac20-28fd-7882-a596-54677beec6fd";
const MESSAGE_ID = "019fac20-2b80-756f-8914-21748c36d51b";
const MESSAGE_TEXT = "Which visible traits support this identification?";

function mockRpcClient(
  response: { data: unknown; error: { message: string } | null },
  observed: {
    name?: string;
    arguments?: Record<string, unknown>;
  } = {},
): SupabaseClient {
  return {
    rpc(name: string, arguments_: Record<string, unknown>) {
      observed.name = name;
      observed.arguments = arguments_;
      return {
        abortSignal() {
          return Promise.resolve(response);
        },
      };
    },
  } as unknown as SupabaseClient;
}

Deno.test("atomic Field Chat admission validates and returns its exact bound row", async () => {
  const observed: {
    name?: string;
    arguments?: Record<string, unknown>;
  } = {};
  const message = {
    id: MESSAGE_ID,
    conversation_id: CONVERSATION_ID,
    scan_id: SUBJECT_ID,
    user_id: USER_ID,
    role: "user",
    message_text: MESSAGE_TEXT,
    client_message_id: REQUEST_ID,
  };
  const client = mockRpcClient({
    data: [{ message, is_replay: false, sends_today: 4 }],
    error: null,
  }, observed);

  assertEquals(
    await reserveFieldChatSend<typeof message>(client, {
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      subjectType: "insight",
      subjectId: SUBJECT_ID,
      messageText: MESSAGE_TEXT,
      clientMessageId: REQUEST_ID,
    }),
    {
      message,
      isReplay: false,
      sendsToday: 4,
    },
  );
  assertEquals(observed.name, "reserve_field_chat_send");
  assertEquals(observed.arguments, {
    p_user_id: USER_ID,
    p_conversation_id: CONVERSATION_ID,
    p_subject_type: "insight",
    p_subject_id: SUBJECT_ID,
    p_message_text: MESSAGE_TEXT,
    p_client_message_id: REQUEST_ID,
  });
});

Deno.test("atomic Field Chat admission rejects malformed or contradictory rows", async () => {
  for (
    const message of [
      null,
      {
        id: MESSAGE_ID,
        conversation_id: CONVERSATION_ID,
        post_id: SUBJECT_ID,
        user_id: USER_ID,
        role: "user",
        message_text: "A different question",
        client_message_id: REQUEST_ID,
      },
      {
        id: MESSAGE_ID,
        conversation_id: CONVERSATION_ID,
        post_id: SUBJECT_ID,
        user_id: USER_ID,
        role: "assistant",
        message_text: MESSAGE_TEXT,
        client_message_id: REQUEST_ID,
      },
    ]
  ) {
    const error = await assertRejects(
      () =>
        reserveFieldChatSend(
          mockRpcClient({
            data: [{ message, is_replay: false, sends_today: 1 }],
            error: null,
          }),
          {
            userId: USER_ID,
            conversationId: CONVERSATION_ID,
            subjectType: "explore",
            subjectId: SUBJECT_ID,
            messageText: MESSAGE_TEXT,
            clientMessageId: REQUEST_ID,
          },
        ),
      PublicHttpError,
    );
    assertEquals(error.code, "field_chat_admission_unavailable");
  }
});

Deno.test("atomic Field Chat admission validates a dictionary subject row", async () => {
  const message = {
    id: MESSAGE_ID,
    conversation_id: CONVERSATION_ID,
    species_dictionary_id: SUBJECT_ID,
    user_id: USER_ID,
    role: "user",
    message_text: MESSAGE_TEXT,
    client_message_id: REQUEST_ID,
  };
  const observed: {
    name?: string;
    arguments?: Record<string, unknown>;
  } = {};
  assertEquals(
    await reserveFieldChatSend<typeof message>(
      mockRpcClient({
        data: [{ message, is_replay: true, sends_today: 7 }],
        error: null,
      }, observed),
      {
        userId: USER_ID,
        conversationId: CONVERSATION_ID,
        subjectType: "species_dictionary",
        subjectId: SUBJECT_ID,
        messageText: MESSAGE_TEXT,
        clientMessageId: REQUEST_ID,
      },
    ),
    { message, isReplay: true, sendsToday: 7 },
  );
  assertEquals(observed.arguments?.p_subject_type, "species_dictionary");
});

Deno.test("atomic Field Chat admission maps stable database failures", async () => {
  const cases = [
    ["field_chat_idempotency_conflict", 409],
    ["field_chat_send_in_progress", 503],
    ["field_chat_daily_limit_reached", 429],
    ["field_chat_conversation_limit_reached", 429],
    ["field_chat_conversation_not_found", 404],
    ["field_chat_access_forbidden", 403],
    ["field_chat_invalid_request", 400],
    ["unexpected database failure", 503],
  ] as const;

  for (const [databaseMessage, expectedStatus] of cases) {
    const error = await assertRejects(
      () =>
        reserveFieldChatSend(
          mockRpcClient({
            data: null,
            error: { message: databaseMessage },
          }),
          {
            userId: USER_ID,
            conversationId: CONVERSATION_ID,
            subjectType: "insight",
            subjectId: SUBJECT_ID,
            messageText: MESSAGE_TEXT,
            clientMessageId: REQUEST_ID,
          },
        ),
      PublicHttpError,
    );
    assertEquals(error.status, expectedStatus, databaseMessage);
  }
});

Deno.test("stale Field Chat quota recovery accepts only a boolean RPC result", async () => {
  const observed: {
    name?: string;
    arguments?: Record<string, unknown>;
  } = {};
  assertEquals(
    await recoverStaleFieldChatQuota(
      mockRpcClient({ data: true, error: null }, observed),
      {
        userId: USER_ID,
        operation: "insight_chat_reply",
        requestId: REQUEST_ID,
        conversationId: CONVERSATION_ID,
        subjectId: SUBJECT_ID,
      },
    ),
    true,
  );
  assertEquals(observed.name, "recover_stale_field_chat_quota");

  const error = await assertRejects(
    () =>
      recoverStaleFieldChatQuota(
        mockRpcClient({ data: "true", error: null }),
        {
          userId: USER_ID,
          operation: "explore_post_chat_reply",
          requestId: REQUEST_ID,
          conversationId: CONVERSATION_ID,
          subjectId: SUBJECT_ID,
        },
      ),
    PublicHttpError,
  );
  assertEquals(error.code, "field_chat_recovery_unavailable");

  assertEquals(
    await recoverStaleFieldChatQuota(
      mockRpcClient({ data: false, error: null }),
      {
        userId: USER_ID,
        operation: "species_dictionary_chat_reply",
        requestId: REQUEST_ID,
        conversationId: CONVERSATION_ID,
        subjectId: SUBJECT_ID,
      },
    ),
    false,
  );
});
