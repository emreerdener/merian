import { assertEquals } from "@std/assert";
import {
  deriveFieldChatAssistantMessageId,
  fieldChatAssistantMetadata,
  fieldChatFeatureFeedbackPayload,
  fieldChatFeedbackPayload,
  fieldChatMessageRequestId,
  fieldChatPromptSuggestionsPayload,
  fieldChatSummaryPayload,
  fieldChatThreadPayload,
  fieldChatUserMessageForRequest,
  isFieldChatRequestComplete,
  waitForFieldChatRequestCompletion,
} from "./fieldChatResponse.ts";

const SUBJECT_ID = "019fabf7-b988-7a5f-bc42-b2123a37a5ed";
const CONVERSATION_ID = "019fabf7-bcf7-768c-a9e7-5cb30cfa6439";
const MESSAGE_ID = "019fabf7-bf6d-74b9-9f35-e4cb1bcf05ea";

Deno.test("Field Chat thread payload always echoes its subject and v1 limits", () => {
  assertEquals(
    fieldChatThreadPayload(
      SUBJECT_ID,
      CONVERSATION_ID,
      [{ id: MESSAGE_ID }],
      7,
    ),
    {
      subject_id: SUBJECT_ID,
      conversation_id: CONVERSATION_ID,
      messages: [{ id: MESSAGE_ID }],
      limits: {
        max_user_message_chars: 600,
        max_messages_per_conversation: 30,
        daily_send_limit: 20,
        sends_remaining_today: 13,
      },
    },
  );
  assertEquals(
    fieldChatThreadPayload(SUBJECT_ID, null, [], 25).limits
      .sends_remaining_today,
    0,
  );
});

Deno.test("Field Chat action payloads always echo their exact subject", async () => {
  assertEquals(
    fieldChatFeedbackPayload(SUBJECT_ID, MESSAGE_ID, "helpful"),
    {
      ok: true,
      subject_id: SUBJECT_ID,
      message_id: MESSAGE_ID,
      rating: "helpful",
    },
  );
  assertEquals(
    fieldChatFeatureFeedbackPayload(SUBJECT_ID, MESSAGE_ID, null),
    {
      ok: true,
      subject_id: SUBJECT_ID,
      id: MESSAGE_ID,
      sentiment: null,
    },
  );
  assertEquals(
    fieldChatSummaryPayload(SUBJECT_ID, "Compared two saved traits."),
    {
      subject_id: SUBJECT_ID,
      summary_text: "Compared two saved traits.",
    },
  );
  assertEquals(
    fieldChatPromptSuggestionsPayload(
      SUBJECT_ID,
      CONVERSATION_ID,
      [{ text: "Which trait matters?", category: "evidence" }],
    ),
    {
      subject_id: SUBJECT_ID,
      conversation_id: CONVERSATION_ID,
      prompts: [{ text: "Which trait matters?", category: "evidence" }],
    },
  );

  const userMessage = {
    role: "user",
    client_message_id: MESSAGE_ID,
    safety_metadata: null,
  };
  const assistantMessage = {
    role: "assistant",
    client_message_id: null,
    safety_metadata: fieldChatAssistantMetadata(MESSAGE_ID.toUpperCase(), {
      source: "model",
    }),
  };
  assertEquals(fieldChatMessageRequestId(userMessage), MESSAGE_ID);
  assertEquals(fieldChatMessageRequestId(assistantMessage), MESSAGE_ID);
  assertEquals(
    fieldChatUserMessageForRequest(
      [assistantMessage, userMessage],
      MESSAGE_ID.toUpperCase(),
    ),
    userMessage,
  );
  assertEquals(
    isFieldChatRequestComplete([userMessage, assistantMessage], MESSAGE_ID),
    true,
  );
  assertEquals(
    isFieldChatRequestComplete([userMessage], MESSAGE_ID),
    false,
  );
  assertEquals(
    await waitForFieldChatRequestCompletion(
      [userMessage],
      MESSAGE_ID,
      () => Promise.resolve([userMessage, assistantMessage]),
      [0],
    ),
    [userMessage, assistantMessage],
  );
  const assistantId = await deriveFieldChatAssistantMessageId(
    CONVERSATION_ID,
    MESSAGE_ID,
  );
  assertEquals(
    await deriveFieldChatAssistantMessageId(
      CONVERSATION_ID.toUpperCase(),
      MESSAGE_ID.toUpperCase(),
    ),
    assistantId,
  );
  assertEquals(
    /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(assistantId),
    true,
  );
});
