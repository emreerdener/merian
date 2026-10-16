import type { SupabaseClient } from "@supabase/supabase-js";
import {
  InsightChatContextAdmissionError,
  type InsightChatContextAdmissionRequest,
  parseInsightChatContextAdmission,
} from "./contextAdmission.ts";
import { validateStoredTurnRequest } from "./storedContext.ts";
import { resolveStoredInsightChatTurn } from "./storedContextRepository.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  storedUUID,
} from "./storedContextContract.ts";

export interface ProtectedInsightChatContextRequest
  extends InsightChatContextAdmissionRequest {
  readonly reservationId: string;
  readonly leaseToken: string;
}
function validateRequest(input: ProtectedInsightChatContextRequest) {
  boundedStoredJSON(input, 8192);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
    "conversationId",
    "reservationId",
    "leaseToken",
  ]);
  const turn = validateStoredTurnRequest({
    ownerId: input.ownerId,
    scanId: input.scanId,
    clientMessageId: input.clientMessageId,
    messageText: input.messageText,
    displayedTicket: input.displayedTicket,
  });
  const admission = immutableStoredCopy({
    ...turn,
    conversationId: storedUUID(input.conversationId),
  });
  return immutableStoredCopy({
    turn,
    admission,
    reservationId: storedUUID(input.reservationId),
    leaseToken: storedUUID(input.leaseToken),
  });
}
const protectedDenials: Readonly<Record<string, readonly string[]>> = {
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
    "field_chat_execution_held",
    "field_chat_execution_unavailable",
  ],
};
/** One exact funding-bound write. A returned replay is recovery, never dispatch permission. */
export async function admitProtectedInsightChatContext(
  client: SupabaseClient,
  input: ProtectedInsightChatContextRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const { admission, reservationId, leaseToken } = validateRequest(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      "reserve_protected_insight_chat_send_with_context",
      {
        p_user_id: admission.ownerId,
        p_conversation_id: admission.conversationId,
        p_scan_id: admission.scanId,
        p_message_text: admission.messageText,
        p_client_message_id: admission.clientMessageId,
        p_displayed_ticket: admission.displayedTicket,
        p_context_version: 1,
        p_reservation_id: reservationId,
        p_lease_token: leaseToken,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      const rejected = Object.hasOwn(protectedDenials, error.code) &&
        protectedDenials[error.code].includes(error.message);
      throw new InsightChatContextAdmissionError(
        rejected ? error.message : "field_chat_context_unavailable",
        rejected ? "rejected" : "unknown",
      );
    }
    return parseInsightChatContextAdmission(data, admission);
  } catch (error) {
    if (error instanceof InsightChatContextAdmissionError) throw error;
    throw new InsightChatContextAdmissionError(
      "field_chat_context_unavailable",
      "unknown",
    );
  }
}
/** Unknown writes get at most one exact read. Neither absence nor recovery grants provider permission. */
export async function admitOrRecoverProtectedInsightChatContext(
  client: SupabaseClient,
  input: ProtectedInsightChatContextRequest,
  signal: AbortSignal,
) {
  // Copy every field before any await; never borrow a changed caller ticket.
  const frozen = validateRequest(input);
  const request = immutableStoredCopy({
    ...frozen.admission,
    reservationId: frozen.reservationId,
    leaseToken: frozen.leaseToken,
  });
  try {
    const admission = await admitProtectedInsightChatContext(
      client,
      request,
      signal,
    );
    if (signal.aborted) {
      throw new InsightChatContextAdmissionError(
        "field_chat_context_unavailable",
        "unknown",
      );
    }
    return {
      kind: admission.isReplay ? "replayed" as const : "admitted" as const,
      admission,
    };
  } catch (error) {
    if (
      !(error instanceof InsightChatContextAdmissionError) ||
      error.transactionOutcome !== "unknown"
    ) throw error;
    if (!signal.aborted) {
      try {
        const recovered = await resolveStoredInsightChatTurn(
          client,
          frozen.turn,
          signal,
        );
        if (!signal.aborted && recovered.found) {
          return { kind: "recovered" as const, recovered };
        }
      } catch {
        // No read result proves that a timed-out writer cannot still commit.
      }
    }
    throw new InsightChatContextAdmissionError(
      "field_chat_context_unavailable",
      "unknown",
    );
  }
}
