import type { SupabaseClient } from "@supabase/supabase-js";
import { validateStoredTurnRequest } from "./storedContext.ts";
import type { ProtectedChatSend } from "./protectedSendContract.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  storedUUID,
} from "./storedContextContract.ts";
import { StoredInsightChatRecoveryError } from "./storedContextRepository.ts";

/** No answer, thread, provider capability or replacement request is fabricated. */
export function parseChatNoAdmission(value: unknown, input: ProtectedChatSend) {
  const request = validateStoredTurnRequest(input.turn);
  const conversationId = storedUUID(input.conversationId);
  boundedStoredJSON(value, 2048);
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return invalidStoredContext();
  }
  const status = (value as Record<string, unknown>).status;
  if (status === "held" || status === "fresh_candidate") {
    exactStoredObject(value, ["status"]);
    return status === "held"
      ? immutableStoredCopy({ status: "held" as const })
      : immutableStoredCopy({ status: "fresh_candidate" as const });
  }
  const row = exactStoredObject(value, [
    "status",
    "context_version",
    "scan_id",
    "conversation_id",
    "client_message_id",
    "reason",
  ]);
  if (
    status !== "not_admitted" || row.context_version !== 1 ||
    storedUUID(row.scan_id) !== request.scanId ||
    storedUUID(row.conversation_id) !== conversationId ||
    storedUUID(row.client_message_id) !== request.clientMessageId ||
    row.reason !== "displayed_identification_changed"
  ) return invalidStoredContext();
  return immutableStoredCopy({
    status: "not_admitted" as const,
    context_version: 1 as const,
    scan_id: request.scanId,
    conversation_id: conversationId,
    client_message_id: request.clientMessageId,
    reason: "displayed_identification_changed" as const,
  });
}
export type ChatNoAdmissionProof = Extract<
  ReturnType<typeof parseChatNoAdmission>,
  { status: "not_admitted" }
>;

async function exactBoundary(
  client: SupabaseClient,
  input: ProtectedChatSend,
  signal: AbortSignal,
  operation:
    | "get_insight_chat_no_admission"
    | "seal_unadmitted_insight_chat_request",
) {
  signal.throwIfAborted();
  const turn = validateStoredTurnRequest(input.turn);
  const saved = immutableStoredCopy({
    turn,
    conversationId: storedUUID(input.conversationId),
  });
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    const { data, error } = await client.rpc(operation, {
      p_user_id: turn.ownerId,
      p_scan_id: turn.scanId,
      p_client_message_id: turn.clientMessageId,
      p_conversation_id: saved.conversationId,
      p_message_text: turn.messageText,
      p_displayed_ticket: turn.displayedTicket,
      p_context_version: 1,
    }).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      if (
        error.code === "P0002" &&
        error.message === "field_chat_subject_not_found"
      ) {
        throw new StoredInsightChatRecoveryError(error.message, 404);
      }
      if (
        error.code === "23505" &&
        error.message === "field_chat_idempotency_conflict"
      ) {
        throw new StoredInsightChatRecoveryError(error.message, 409);
      }
      throw new Error("held");
    }
    const result = parseChatNoAdmission(data, saved);
    if (
      operation === "seal_unadmitted_insight_chat_request" &&
      result.status === "fresh_candidate"
    ) {
      return invalidStoredContext();
    }
    return result;
  } catch (error) {
    signal.throwIfAborted();
    if (error instanceof StoredInsightChatRecoveryError) throw error;
    throw new StoredInsightChatRecoveryError(
      "field_chat_context_unavailable",
      503,
    );
  }
}
/** Only an exact terminal seal is proof. Absence merely permits fresh preflight. */
export function readChatNoAdmission(
  client: SupabaseClient,
  input: ProtectedChatSend,
  signal: AbortSignal,
) {
  return exactBoundary(client, input, signal, "get_insight_chat_no_admission");
}
/** One write after typed stale-ticket denial; an unknown reply is never retried. */
export function sealChatNoAdmission(
  client: SupabaseClient,
  input: ProtectedChatSend,
  signal: AbortSignal,
) {
  return exactBoundary(
    client,
    input,
    signal,
    "seal_unadmitted_insight_chat_request",
  );
}
