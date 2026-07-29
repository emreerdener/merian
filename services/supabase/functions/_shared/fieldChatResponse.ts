import {
  DAILY_SEND_LIMIT,
  InsightChatFeatureFeedbackSentiment,
  InsightChatFeedbackRating,
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
} from "../insight-chat/types.ts";

interface FieldChatRequestMessage {
  role: string;
  client_message_id: string | null;
  safety_metadata: Record<string, unknown> | null;
}

const FIELD_CHAT_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function canonicalFieldChatUuid(value: unknown): string | null {
  return typeof value === "string" && FIELD_CHAT_UUID_PATTERN.test(value)
    ? value.toLowerCase()
    : null;
}

export function fieldChatAssistantMetadata(
  requestId: string,
  metadata: Record<string, unknown> = {},
): Record<string, unknown> {
  const canonicalRequestId = canonicalFieldChatUuid(requestId);
  if (!canonicalRequestId) {
    throw new TypeError("Field Chat request id must be a UUID.");
  }
  return {
    ...metadata,
    request_id: canonicalRequestId,
  };
}

export function fieldChatMessageRequestId(
  message: FieldChatRequestMessage,
): string | null {
  if (message.role === "user") {
    return canonicalFieldChatUuid(message.client_message_id);
  }
  const requestId = message.safety_metadata?.request_id;
  return canonicalFieldChatUuid(requestId);
}

export function fieldChatUserMessageForRequest<
  Message extends FieldChatRequestMessage,
>(
  messages: Message[],
  requestId: string,
): Message | null {
  const canonicalRequestId = canonicalFieldChatUuid(requestId);
  if (!canonicalRequestId) return null;
  return messages.find((message) =>
    message.role === "user" &&
    fieldChatMessageRequestId(message) === canonicalRequestId
  ) ?? null;
}

export function isFieldChatRequestComplete(
  messages: FieldChatRequestMessage[],
  requestId: string,
): boolean {
  const canonicalRequestId = canonicalFieldChatUuid(requestId);
  if (!canonicalRequestId) return false;
  let hasUserMessage = false;
  let hasAssistantMessage = false;
  for (const message of messages) {
    if (fieldChatMessageRequestId(message) !== canonicalRequestId) continue;
    hasUserMessage ||= message.role === "user";
    hasAssistantMessage ||= message.role === "assistant";
  }
  return hasUserMessage && hasAssistantMessage;
}

export async function deriveFieldChatAssistantMessageId(
  conversationId: string,
  requestId: string,
): Promise<string> {
  const canonicalConversationId = canonicalFieldChatUuid(conversationId);
  const canonicalRequestId = canonicalFieldChatUuid(requestId);
  if (!canonicalConversationId || !canonicalRequestId) {
    throw new TypeError(
      "Field Chat conversation and request ids must be UUIDs.",
    );
  }

  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(
        `merian-field-chat-assistant-v1:${canonicalConversationId}:${canonicalRequestId}`,
      ),
    ),
  ).slice(0, 16);
  // RFC 9562 UUIDv8: a deterministic, non-reversible assistant-row identity.
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = Array.from(
    digest,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

const FIELD_CHAT_REPLAY_DELAYS_MS = [250, 500, 1000, 2000, 4000, 6000];

export async function waitForFieldChatRequestCompletion<
  Message extends FieldChatRequestMessage,
>(
  initialMessages: Message[],
  requestId: string,
  loadMessages: () => Promise<Message[]>,
  delaysMs: number[] = FIELD_CHAT_REPLAY_DELAYS_MS,
): Promise<Message[] | null> {
  if (isFieldChatRequestComplete(initialMessages, requestId)) {
    return initialMessages;
  }
  for (const delayMs of delaysMs) {
    await new Promise<void>((resolve) => setTimeout(resolve, delayMs));
    const messages = await loadMessages();
    if (isFieldChatRequestComplete(messages, requestId)) return messages;
  }
  return null;
}

export function fieldChatThreadPayload<Message>(
  subjectId: string,
  conversationId: string | null,
  messages: Message[],
  sendsToday: number,
) {
  return {
    subject_id: subjectId,
    conversation_id: conversationId,
    messages,
    limits: {
      max_user_message_chars: MAX_USER_MESSAGE_CHARS,
      max_messages_per_conversation: MAX_MESSAGES_PER_CONVERSATION,
      daily_send_limit: DAILY_SEND_LIMIT,
      sends_remaining_today: Math.max(0, DAILY_SEND_LIMIT - sendsToday),
    },
  };
}

export function fieldChatFeedbackPayload(
  subjectId: string,
  messageId: string,
  rating: InsightChatFeedbackRating,
) {
  return {
    ok: true,
    subject_id: subjectId,
    message_id: messageId,
    rating,
  };
}

export function fieldChatFeatureFeedbackPayload(
  subjectId: string,
  id: string,
  sentiment: InsightChatFeatureFeedbackSentiment | null,
) {
  return {
    ok: true,
    subject_id: subjectId,
    id,
    sentiment,
  };
}

export function fieldChatSummaryPayload(
  subjectId: string,
  summaryText: string,
) {
  return {
    subject_id: subjectId,
    summary_text: summaryText,
  };
}

export function fieldChatPromptSuggestionsPayload<Prompt>(
  subjectId: string,
  conversationId: string | null,
  prompts: Prompt[],
) {
  return {
    subject_id: subjectId,
    conversation_id: conversationId,
    prompts,
  };
}
