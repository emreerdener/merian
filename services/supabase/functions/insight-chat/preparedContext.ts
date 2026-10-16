import type { SupabaseClient } from "@supabase/supabase-js";
import {
  boundedStoredJSON,
  type ChatContextTicket,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  parseChatContextTicket,
  sameChatContextTicket,
  storedUUID,
  validateStoredScanContext,
} from "./storedContextContract.ts";

export interface InsightChatContextPreflightRequest {
  readonly ownerId: string;
  readonly scanId: string;
  readonly displayedTicket: ChatContextTicket;
}
function validateRequest(input: InsightChatContextPreflightRequest) {
  boundedStoredJSON(input, 2048);
  exactStoredObject(input, ["ownerId", "scanId", "displayedTicket"]);
  const ownerId = storedUUID(input.ownerId), scanId = storedUUID(input.scanId);
  const displayedTicket = parseChatContextTicket(input.displayedTicket);
  if (displayedTicket?.analysis_id === scanId) return invalidStoredContext();
  return immutableStoredCopy({ ownerId, scanId, displayedTicket });
}
/** Fresh eligibility data only; this never fabricates an admitted turn/prefix. */
export function parsePreparedInsightChatContext(
  value: unknown,
  input: InsightChatContextPreflightRequest,
) {
  const request = validateRequest(input);
  boundedStoredJSON(value, 131072);
  const row = exactStoredObject(value, [
    "context_version",
    "source_kind",
    "displayed_ticket",
    "scan_context",
  ]);
  const ticket = parseChatContextTicket(row.displayed_ticket);
  if (
    row.context_version !== 1 ||
    !sameChatContextTicket(ticket, request.displayedTicket) ||
    row.source_kind !==
      (ticket === null ? "legacy_scan_v1" : "analysis_history_v1")
  ) {
    return invalidStoredContext();
  }
  return immutableStoredCopy({
    context_version: 1 as const,
    source_kind: ticket === null
      ? "legacy_scan_v1" as const
      : "analysis_history_v1" as const,
    displayed_ticket: ticket,
    scan_context: validateStoredScanContext(row.scan_context),
  });
}
export type PreparedInsightChatContext = ReturnType<
  typeof parsePreparedInsightChatContext
>;
export class InsightChatContextPreflightError extends Error {
  constructor(
    readonly code:
      | "field_chat_subject_not_found"
      | "field_chat_context_conflict"
      | "field_chat_context_unavailable",
    readonly status: 404 | 409 | 503,
  ) {
    super(code);
    this.name = "InsightChatContextPreflightError";
  }
}
/** No admission, entitlement or provider grant is implied by this bounded read. */
export async function prepareInsightChatSendContext(
  client: SupabaseClient,
  input: InsightChatContextPreflightRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = validateRequest(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      "prepare_insight_chat_send_context",
      {
        p_user_id: request.ownerId,
        p_scan_id: request.scanId,
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      if (
        error.code === "P0002" &&
        error.message === "field_chat_subject_not_found"
      ) {
        throw new InsightChatContextPreflightError(error.message, 404);
      }
      if (
        error.code === "40001" &&
        error.message === "field_chat_context_conflict"
      ) {
        throw new InsightChatContextPreflightError(error.message, 409);
      }
      throw new InsightChatContextPreflightError(
        "field_chat_context_unavailable",
        503,
      );
    }
    return parsePreparedInsightChatContext(data, request);
  } catch (error) {
    signal.throwIfAborted();
    if (error instanceof InsightChatContextPreflightError) throw error;
    throw new InsightChatContextPreflightError(
      "field_chat_context_unavailable",
      503,
    );
  }
}
