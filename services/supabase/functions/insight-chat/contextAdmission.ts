import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseStoredInsightChatContext,
  type StoredInsightChatTurnRequest,
  validateStoredTurnRequest,
} from "./storedContext.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  storedObject,
  storedUUID,
} from "./storedContextContract.ts";

export interface InsightChatContextAdmissionRequest
  extends StoredInsightChatTurnRequest {
  readonly conversationId: string;
}
function validateRequest(input: InsightChatContextAdmissionRequest) {
  boundedStoredJSON(input, 8192);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
    "conversationId",
  ]);
  const conversationId = storedUUID(input.conversationId);
  const request = validateStoredTurnRequest({
    ownerId: input.ownerId,
    scanId: input.scanId,
    clientMessageId: input.clientMessageId,
    messageText: input.messageText,
    displayedTicket: input.displayedTicket,
  });
  return immutableStoredCopy({ ...request, conversationId });
}
/** The SQL producer returns the full user row. Validate and project turn identity; unrelated row metadata is not context. */
export function parseInsightChatContextAdmission(
  value: unknown,
  input: InsightChatContextAdmissionRequest,
) {
  const request = validateRequest(input);
  boundedStoredJSON(value, 139264);
  if (!Array.isArray(value) || value.length !== 1) {
    return invalidStoredContext();
  }
  const row = exactStoredObject(value[0], [
    "conversation_id",
    "message",
    "is_replay",
    "sends_today",
    "context_snapshot",
  ]);
  const conversationId = storedUUID(row.conversation_id);
  if (
    typeof row.is_replay !== "boolean" || typeof row.sends_today !== "number" ||
    !Number.isSafeInteger(row.sends_today) || row.sends_today < 0 ||
    row.sends_today > 2147483647
  ) return invalidStoredContext();
  const message = storedObject(row.message);
  const messageId = storedUUID(message.id);
  if (
    message.conversation_id !== conversationId ||
    message.scan_id !== request.scanId || message.user_id !== request.ownerId ||
    message.role !== "user" || message.message_text !== request.messageText ||
    message.client_message_id !== request.clientMessageId
  ) return invalidStoredContext();
  const context = parseStoredInsightChatContext(
    row.context_snapshot,
    request.displayedTicket,
  );
  return immutableStoredCopy({
    conversationId,
    isReplay: row.is_replay,
    sendsToday: row.sends_today,
    message: {
      id: messageId,
      conversation_id: conversationId,
      scan_id: request.scanId,
      user_id: request.ownerId,
      role: "user" as const,
      client_message_id: request.clientMessageId,
      message_text: request.messageText,
    },
    context,
  });
}
export type InsightChatContextAdmission = ReturnType<
  typeof parseInsightChatContextAdmission
>;
/** Rejection describes this RPC transaction only, never the status of an earlier attempt or quota lease. */
export class InsightChatContextAdmissionError extends Error {
  constructor(
    readonly code: string,
    readonly transactionOutcome: "rejected" | "unknown",
  ) {
    super(code);
    this.name = "InsightChatContextAdmissionError";
  }
}
const denials: Readonly<Record<string, readonly string[]>> = {
  "22023": ["field_chat_invalid_request"],
  "P0002": ["field_chat_subject_not_found", "field_chat_user_not_found"],
  "40001": ["field_chat_context_conflict"],
  "23505": ["field_chat_idempotency_conflict"],
  "42501": ["field_chat_access_forbidden"],
  "54000": ["field_chat_conversation_limit_reached"],
  "P0001": ["field_chat_daily_limit_reached"],
  "55000": [
    "field_chat_context_missing",
    "field_chat_context_unavailable",
    "field_chat_send_in_progress",
    "field_chat_admission_cutover_pending",
    "field_chat_admission_cutover_unavailable",
  ],
};
/** One write with no transparent retry. Unknown outcomes require exact read-only recovery. */
export async function admitInsightChatTurnContext(
  client: SupabaseClient,
  input: InsightChatContextAdmissionRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = validateRequest(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      "reserve_insight_chat_send_with_context",
      {
        p_user_id: request.ownerId,
        p_conversation_id: request.conversationId,
        p_scan_id: request.scanId,
        p_message_text: request.messageText,
        p_client_message_id: request.clientMessageId,
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      if (
        Object.hasOwn(denials, error.code) &&
        denials[error.code].includes(error.message)
      ) {
        throw new InsightChatContextAdmissionError(error.message, "rejected");
      }
      throw new InsightChatContextAdmissionError(
        "field_chat_context_unavailable",
        "unknown",
      );
    }
    return parseInsightChatContextAdmission(data, request);
  } catch (error) {
    // Once dispatch began, cancellation is ambiguous too. Do not advertise it
    // as proof that admission did not occur, or copy transport diagnostics out.
    if (error instanceof InsightChatContextAdmissionError) throw error;
    throw new InsightChatContextAdmissionError(
      "field_chat_context_unavailable",
      "unknown",
    );
  }
}
