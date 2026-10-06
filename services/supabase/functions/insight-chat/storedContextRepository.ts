import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseStoredInsightChatResolution,
  type StoredInsightChatTurnRequest,
  validateStoredTurnRequest,
} from "./storedContext.ts";

/** Stable local failures; never expose raw database messages or stored context. */
export class StoredInsightChatRecoveryError extends Error {
  constructor(
    readonly code:
      | "field_chat_subject_not_found"
      | "field_chat_context_missing"
      | "field_chat_idempotency_conflict"
      | "field_chat_context_unavailable",
    readonly status: 404 | 409 | 503,
  ) {
    super(code);
    this.name = "StoredInsightChatRecoveryError";
  }
}

/** One bounded read. Only a decoded found=false permits fresh-send preflight. */
export async function resolveStoredInsightChatTurn(
  client: SupabaseClient,
  input: StoredInsightChatTurnRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = validateStoredTurnRequest(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc("get_insight_chat_turn_context", {
      p_user_id: request.ownerId,
      p_scan_id: request.scanId,
      p_client_message_id: request.clientMessageId,
      p_message_text: request.messageText,
      p_displayed_ticket: request.displayedTicket,
      p_context_version: 1,
    }).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      if (
        error.code === "P0002" &&
        error.message === "field_chat_subject_not_found"
      ) throw new StoredInsightChatRecoveryError(error.message, 404);
      if (
        error.code === "55000" &&
        error.message === "field_chat_context_missing"
      ) throw new StoredInsightChatRecoveryError(error.message, 409);
      if (
        error.code === "23505" &&
        error.message === "field_chat_idempotency_conflict"
      ) throw new StoredInsightChatRecoveryError(error.message, 409);
      throw new StoredInsightChatRecoveryError(
        "field_chat_context_unavailable",
        503,
      );
    }
    return parseStoredInsightChatResolution(data, request);
  } catch (error) {
    signal.throwIfAborted();
    if (error instanceof StoredInsightChatRecoveryError) throw error;
    throw new StoredInsightChatRecoveryError(
      "field_chat_context_unavailable",
      503,
    );
  }
}
