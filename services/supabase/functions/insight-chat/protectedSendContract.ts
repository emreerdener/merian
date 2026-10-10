import type { ChatNoAdmissionProof } from "./noAdmission.ts";
import { normalizeUserMessage } from "./guards.ts";
import {
  LOCAL_REFUSAL_REASONS,
  parseInsightChatCompletion,
} from "./exactCompletion.ts";
import { validateStoredTurnRequest } from "./storedContext.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  parseChatContextTicket,
  storedUUID,
} from "./storedContextContract.ts";
/** New coordinated protocol: legacy thread clients cannot implicitly opt in. */
export function parseProtectedChatSend(ownerId: string, value: unknown) {
  boundedStoredJSON(value, 8192);
  const row = exactStoredObject(value, [
    "action",
    "context_version",
    "scan_id",
    "conversation_id",
    "client_message_id",
    "message_text",
    "displayed_ticket",
  ]);
  if (row.action !== "send" || row.context_version !== 1) {
    return invalidStoredContext();
  }
  const turn = validateStoredTurnRequest({
    ownerId: storedUUID(ownerId),
    scanId: storedUUID(row.scan_id),
    clientMessageId: storedUUID(row.client_message_id),
    messageText: normalizeUserMessage(row.message_text),
    displayedTicket: parseChatContextTicket(row.displayed_ticket),
  });
  return immutableStoredCopy({
    turn,
    conversationId: storedUUID(row.conversation_id),
  });
}
export type ProtectedChatSend = ReturnType<typeof parseProtectedChatSend>;
export type ProtectedChatCompletion = Extract<
  Awaited<ReturnType<typeof parseInsightChatCompletion>>,
  { completed: true }
>;
/** Receipt only. No mutable thread, current selection or quota claims. */
export function protectedChatSendPayload(
  receipt: ProtectedChatCompletion,
): { readonly data: ProtectedChatCompletion & { readonly context_version: 1 } };
export function protectedChatSendPayload(
  receipt: ProtectedChatCompletion | ChatNoAdmissionProof,
):
  | { readonly data: ProtectedChatCompletion & { readonly context_version: 1 } }
  | {
    readonly data: Omit<ChatNoAdmissionProof, "status"> & {
      readonly outcome: "not_admitted";
    };
  };
export function protectedChatSendPayload(
  receipt: ProtectedChatCompletion | ChatNoAdmissionProof,
) {
  if ("status" in receipt) {
    const proof = exactStoredObject(receipt, [
      "status",
      "context_version",
      "scan_id",
      "conversation_id",
      "client_message_id",
      "reason",
    ]);
    if (
      proof.status !== "not_admitted" || proof.context_version !== 1 ||
      proof.reason !== "displayed_identification_changed"
    ) return invalidStoredContext();
    return immutableStoredCopy({
      data: {
        context_version: 1 as const,
        outcome: "not_admitted" as const,
        scan_id: storedUUID(proof.scan_id),
        conversation_id: storedUUID(proof.conversation_id),
        client_message_id: storedUUID(proof.client_message_id),
        reason: "displayed_identification_changed" as const,
      },
    });
  }
  const message = receipt.message;
  if (
    (!message.is_refusal && message.refusal_reason !== null) ||
    (message.model === null
      ? !message.is_refusal ||
        !LOCAL_REFUSAL_REASONS.some((reason) =>
          reason === message.refusal_reason
        )
      : message.model !== "gemini-2.5-flash")
  ) return invalidStoredContext();
  return immutableStoredCopy({
    data: {
      context_version: 1 as const,
      completed: true as const,
      message: receipt.message,
    },
  });
}
