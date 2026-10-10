import {
  boundedStoredJSON,
  type ChatContextTicket,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  parseChatContextTicket,
  sameChatContextTicket,
  storedText,
  storedUUID,
  validateStoredScanContext,
} from "./storedContextContract.ts";

export interface StoredInsightChatTurnRequest {
  readonly ownerId: string;
  readonly scanId: string;
  readonly clientMessageId: string;
  readonly messageText: string;
  readonly displayedTicket: ChatContextTicket;
}
export function validateStoredTurnRequest(
  request: StoredInsightChatTurnRequest,
) {
  boundedStoredJSON(request, 8192);
  exactStoredObject(request, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
  ]);
  storedUUID(request.ownerId);
  storedUUID(request.scanId);
  storedUUID(request.clientMessageId);
  const text = storedText(request.messageText, 600);
  // PostgreSQL btrim removes U+0020 only; do not normalize the original retry.
  if (!text || text !== text.replace(/^ +| +$/g, "")) {
    return invalidStoredContext();
  }
  const ticket = parseChatContextTicket(request.displayedTicket);
  if (ticket?.analysis_id === request.scanId) return invalidStoredContext();
  return immutableStoredCopy({ ...request, displayedTicket: ticket });
}
export function parseStoredInsightChatContext(
  value: unknown,
  expected: ChatContextTicket,
) {
  boundedStoredJSON(value, 131072);
  const row = exactStoredObject(value, [
    "context_version",
    "source_kind",
    "displayed_ticket",
    "scan_context",
    "conversation_prefix",
  ]);
  const ticket = parseChatContextTicket(row.displayed_ticket);
  if (
    row.context_version !== 1 || !sameChatContextTicket(ticket, expected) ||
    row.source_kind !==
      (ticket === null ? "legacy_scan_v1" : "analysis_history_v1")
  ) return invalidStoredContext();
  const context = validateStoredScanContext(row.scan_context);
  if (
    !Array.isArray(row.conversation_prefix) ||
    row.conversation_prefix.length > 12
  ) return invalidStoredContext();
  const prefix = row.conversation_prefix.map((entry) => {
    const message = exactStoredObject(entry, ["role", "text"]);
    if (message.role !== "user" && message.role !== "assistant") {
      return invalidStoredContext();
    }
    return { role: message.role, text: storedText(message.text, 900) };
  });
  return immutableStoredCopy({
    context_version: 1 as const,
    source_kind: ticket === null
      ? "legacy_scan_v1" as const
      : "analysis_history_v1" as const,
    displayed_ticket: ticket,
    scan_context: context,
    conversation_prefix: prefix,
  });
}
export type StoredInsightChatTurnContext = ReturnType<
  typeof parseStoredInsightChatContext
>;
export function parseStoredInsightChatResolution(
  value: unknown,
  input: StoredInsightChatTurnRequest,
) {
  const request = validateStoredTurnRequest(input);
  boundedStoredJSON(value, 139264);
  const marker = exactStoredObject(
    value,
    typeof value === "object" && value !== null && "found" in value &&
      value.found === true
      ? ["context_version", "found", "message", "context_snapshot"]
      : ["context_version", "found"],
  );
  if (marker.context_version !== 1) return invalidStoredContext();
  if (marker.found === false) return Object.freeze({ found: false as const });
  if (marker.found !== true) return invalidStoredContext();
  const message = exactStoredObject(marker.message, [
    "id",
    "conversation_id",
    "scan_id",
    "user_id",
    "role",
    "client_message_id",
    "message_text",
  ]);
  const id = storedUUID(message.id),
    conversationId = storedUUID(message.conversation_id);
  if (
    message.role !== "user" || message.scan_id !== request.scanId ||
    message.user_id !== request.ownerId ||
    message.client_message_id !== request.clientMessageId ||
    message.message_text !== request.messageText
  ) return invalidStoredContext();
  const context = parseStoredInsightChatContext(
    marker.context_snapshot,
    request.displayedTicket,
  );
  return immutableStoredCopy({
    found: true as const,
    message: {
      id,
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
export type StoredInsightChatResolution = ReturnType<
  typeof parseStoredInsightChatResolution
>;
