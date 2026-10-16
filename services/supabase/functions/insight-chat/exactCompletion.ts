import type { SupabaseClient } from "@supabase/supabase-js";
import { deriveFieldChatAssistantMessageId } from "../_shared/fieldChat/response.ts";
import { InsightChatContextAdmissionError } from "./contextAdmission.ts";
import { refusalAnswer } from "./guards.ts";
import {
  type StoredInsightChatTurnRequest,
  validateStoredTurnRequest,
} from "./storedContext.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  storedText,
  storedUUID,
} from "./storedContextContract.ts";

export const LOCAL_REFUSAL_REASONS = [
  "foraging_or_ingestion",
  "medical_or_veterinary",
  "dangerous_handling",
  "legal_or_collection",
] as const;
export type LocalRefusalReason = typeof LOCAL_REFUSAL_REASONS[number];
export interface InsightChatCompletionRequest
  extends StoredInsightChatTurnRequest {
  readonly messageId: string;
  readonly conversationId: string;
}
export interface InsightChatLocalRefusalRequest
  extends StoredInsightChatTurnRequest {
  readonly conversationId: string;
  readonly reason: LocalRefusalReason;
}
function original(input: StoredInsightChatTurnRequest) {
  return validateStoredTurnRequest({
    ownerId: input.ownerId,
    scanId: input.scanId,
    clientMessageId: input.clientMessageId,
    messageText: input.messageText,
    displayedTicket: input.displayedTicket,
  });
}
function completionRequest(input: InsightChatCompletionRequest) {
  boundedStoredJSON(input, 8192);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
    "messageId",
    "conversationId",
  ]);
  return immutableStoredCopy({
    ...original(input),
    messageId: storedUUID(input.messageId),
    conversationId: storedUUID(input.conversationId),
  });
}
export function validateInsightChatLocalRefusal(
  input: InsightChatLocalRefusalRequest,
) {
  boundedStoredJSON(input, 8192);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
    "conversationId",
    "reason",
  ]);
  if (!LOCAL_REFUSAL_REASONS.includes(input.reason)) {
    return invalidStoredContext();
  }
  return immutableStoredCopy({
    ...original(input),
    conversationId: storedUUID(input.conversationId),
    reason: input.reason,
  });
}
export async function parseInsightChatCompletion(
  value: unknown,
  input: StoredInsightChatTurnRequest,
  conversationId?: string,
) {
  const request = original(input);
  boundedStoredJSON(value, 32768);
  const row = exactStoredObject(
    value,
    typeof value === "object" && value !== null && "completed" in value &&
      value.completed === true
      ? ["context_version", "completed", "message"]
      : ["context_version", "completed"],
  );
  if (row.context_version !== 1) return invalidStoredContext();
  if (row.completed === false) {
    return Object.freeze({ completed: false as const });
  }
  if (row.completed !== true) return invalidStoredContext();
  const message = exactStoredObject(row.message, [
    "id",
    "conversation_id",
    "scan_id",
    "role",
    "text",
    "client_message_id",
    "model",
    "is_refusal",
    "refusal_reason",
    "created_at",
  ]);
  const conversation = storedUUID(message.conversation_id),
    id = storedUUID(message.id);
  const text = storedText(message.text, 4000);
  const model = message.model === null ? null : storedText(message.model, 200);
  const reason = message.refusal_reason === null
    ? null
    : storedText(message.refusal_reason, 100);
  if (
    (conversationId !== undefined && conversation !== conversationId) ||
    message.scan_id !== request.scanId ||
    message.client_message_id !== request.clientMessageId ||
    message.role !== "assistant" || typeof message.is_refusal !== "boolean" ||
    !text.trim() || model === "" || reason === "" ||
    typeof message.created_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(message.created_at) ||
    !Number.isFinite(Date.parse(message.created_at))
  ) return invalidStoredContext();
  if (
    id !==
      await deriveFieldChatAssistantMessageId(
        conversation,
        request.clientMessageId,
      )
  ) return invalidStoredContext();
  return immutableStoredCopy({
    completed: true as const,
    message: {
      id,
      conversation_id: conversation,
      scan_id: request.scanId,
      role: "assistant" as const,
      text,
      client_message_id: request.clientMessageId,
      model,
      is_refusal: message.is_refusal,
      refusal_reason: reason,
      created_at: message.created_at,
    },
  });
}
const denials: Readonly<Record<string, readonly string[]>> = {
  "22023": ["field_chat_invalid_request"],
  "P0002": ["field_chat_subject_not_found", "field_chat_user_not_found"],
  "23505": ["field_chat_idempotency_conflict"],
  "40001": ["field_chat_context_conflict"],
  "42501": ["field_chat_access_forbidden"],
  "54000": ["field_chat_conversation_limit_reached"],
  "P0001": ["field_chat_daily_limit_reached"],
  "55000": [
    "field_chat_completion_held",
    "field_chat_context_missing",
    "field_chat_context_unavailable",
    "field_chat_execution_held",
    "field_chat_execution_unavailable",
    "field_chat_send_in_progress",
    "field_chat_admission_cutover_pending",
    "field_chat_admission_cutover_unavailable",
  ],
};
function unavailable(error: unknown): never {
  if (error instanceof InsightChatContextAdmissionError) throw error;
  throw new InsightChatContextAdmissionError(
    "field_chat_completion_unavailable",
    "unknown",
  );
}
function checkError(error: { code: string; message: string } | null) {
  if (!error) return;
  if (
    Object.hasOwn(denials, error.code) &&
    denials[error.code].includes(error.message)
  ) throw new InsightChatContextAdmissionError(error.message, "rejected");
  unavailable(error);
}
/** One exact read; incomplete is never permission to dispatch or complete a turn. */
export async function readInsightChatCompletion(
  client: SupabaseClient,
  input: InsightChatCompletionRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = completionRequest(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    const { data, error } = await client.rpc(
      "get_insight_chat_turn_completion",
      {
        p_user_id: request.ownerId,
        p_scan_id: request.scanId,
        p_client_message_id: request.clientMessageId,
        p_message_text: request.messageText,
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
        p_message_id: request.messageId,
        p_conversation_id: request.conversationId,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    checkError(error);
    const receipt = await parseInsightChatCompletion(
      data,
      request,
      request.conversationId,
    );
    deadline.throwIfAborted();
    return receipt;
  } catch (error) {
    signal.throwIfAborted();
    return unavailable(error);
  }
}
/** One atomic question/context/refusal write. An unknown outcome never retries. */
export async function admitInsightChatLocalRefusal(
  client: SupabaseClient,
  input: InsightChatLocalRefusalRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = validateInsightChatLocalRefusal(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    const { data, error } = await client.rpc(
      "admit_insight_chat_local_refusal",
      {
        p_user_id: request.ownerId,
        p_conversation_id: request.conversationId,
        p_scan_id: request.scanId,
        p_message_text: request.messageText,
        p_client_message_id: request.clientMessageId,
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
        p_refusal_reason: request.reason,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    checkError(error);
    const receipt = await parseInsightChatCompletion(data, request);
    if (
      !receipt.completed || !receipt.message.is_refusal ||
      receipt.message.refusal_reason !== request.reason ||
      receipt.message.text !== refusalAnswer(request.reason) ||
      receipt.message.model !== null
    ) return invalidStoredContext();
    deadline.throwIfAborted();
    return receipt;
  } catch (error) {
    return unavailable(error);
  }
}
