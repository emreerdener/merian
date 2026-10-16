import type { SupabaseClient } from "@supabase/supabase-js";
import { InsightChatContextAdmissionError } from "./contextAdmission.ts";
import {
  type InsightChatCompletionRequest,
  parseInsightChatCompletion,
} from "./exactCompletion.ts";
import { validateStoredTurnRequest } from "./storedContext.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  storedObject,
  storedText,
  storedUUID,
} from "./storedContextContract.ts";

const COUNT_KEYS = [
  "prompt_tokens",
  "candidate_tokens",
  "thinking_tokens",
  "total_tokens",
  "cached_tokens",
] as const;
const MODALITIES = [
  "text",
  "image",
  "audio",
  "video",
  "document",
  "unspecified",
];
function count(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
    value > 2147483647
  ) return invalidStoredContext();
  return value;
}
function modality(value: unknown) {
  const row = storedObject(value);
  if (Object.keys(row).some((key) => !MODALITIES.includes(key))) {
    return invalidStoredContext();
  }
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => [key, count(value)]),
  );
}
export function parseProtectedChatReply(value: unknown) {
  boundedStoredJSON(value, 32768);
  const row = exactStoredObject(value, [
    "answer",
    "model",
    "is_refusal",
    "refusal_reason",
    "usage",
  ]);
  const answer = storedText(row.answer, 4000);
  const reason = row.refusal_reason === null
    ? null
    : storedText(row.refusal_reason, 100);
  if (
    !answer.trim() || answer !== answer.replace(/^ +| +$/g, "") ||
    row.model !== "gemini-2.5-flash" || typeof row.is_refusal !== "boolean" ||
    (reason !== null &&
      (!reason.trim() || reason !== reason.replace(/^ +| +$/g, ""))) ||
    (!row.is_refusal && reason !== null)
  ) return invalidStoredContext();
  let usage = null;
  if (row.usage !== null) {
    const data = exactStoredObject(row.usage, [
      ...COUNT_KEYS,
      "modality_breakdown",
    ]);
    const nullableCount = (value: unknown) =>
      value === null ? null : count(value);
    const counts = {
      prompt_tokens: nullableCount(data.prompt_tokens),
      candidate_tokens: nullableCount(data.candidate_tokens),
      thinking_tokens: nullableCount(data.thinking_tokens),
      total_tokens: nullableCount(data.total_tokens),
      cached_tokens: nullableCount(data.cached_tokens),
    };
    const breakdown = exactStoredObject(data.modality_breakdown, [
      "prompt",
      "cached",
      "candidates",
      "tool",
    ]);
    usage = {
      ...counts,
      modality_breakdown: {
        prompt: modality(breakdown.prompt),
        cached: modality(breakdown.cached),
        candidates: modality(breakdown.candidates),
        tool: modality(breakdown.tool),
      },
    };
  }
  return immutableStoredCopy({
    answer,
    model: "gemini-2.5-flash" as const,
    is_refusal: row.is_refusal,
    refusal_reason: reason,
    usage,
  });
}
export type ProtectedChatReply = ReturnType<typeof parseProtectedChatReply>;
export interface ProtectedChatReplyRequest
  extends InsightChatCompletionRequest {
  readonly reservationId: string;
  readonly leaseToken: string;
  readonly reply: ProtectedChatReply;
}
function request(input: ProtectedChatReplyRequest) {
  boundedStoredJSON(input, 40960);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "messageText",
    "displayedTicket",
    "messageId",
    "conversationId",
    "reservationId",
    "leaseToken",
    "reply",
  ]);
  const original = validateStoredTurnRequest({
    ownerId: input.ownerId,
    scanId: input.scanId,
    clientMessageId: input.clientMessageId,
    messageText: input.messageText,
    displayedTicket: input.displayedTicket,
  });
  return immutableStoredCopy({
    ...original,
    messageId: storedUUID(input.messageId),
    conversationId: storedUUID(input.conversationId),
    reservationId: storedUUID(input.reservationId),
    leaseToken: storedUUID(input.leaseToken),
    reply: parseProtectedChatReply(input.reply),
  });
}
const denials: Readonly<Record<string, readonly string[]>> = {
  "22023": ["field_chat_invalid_reply", "field_chat_invalid_request"],
  "P0002": ["field_chat_subject_not_found"],
  "23505": ["field_chat_reply_conflict", "field_chat_idempotency_conflict"],
  "55000": [
    "field_chat_execution_held",
    "field_chat_context_missing",
    "field_chat_completion_held",
    "field_chat_context_unavailable",
  ],
};
function unknown(): never {
  throw new InsightChatContextAdmissionError(
    "field_chat_completion_unavailable",
    "unknown",
  );
}
function matches(
  receipt: Awaited<ReturnType<typeof parseInsightChatCompletion>>,
  reply: ProtectedChatReply,
) {
  return receipt.completed && receipt.message.text === reply.answer &&
    receipt.message.model === reply.model &&
    receipt.message.is_refusal === reply.is_refusal &&
    receipt.message.refusal_reason === reply.refusal_reason;
}
/** One original-grant-bound write; it cannot admit quota or dispatch a provider. */
async function replyRPC(
  routine:
    | "complete_protected_insight_chat_reply"
    | "get_protected_insight_chat_reply",
  client: SupabaseClient,
  input: ProtectedChatReplyRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const saved = request(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      routine,
      {
        p_user_id: saved.ownerId,
        p_scan_id: saved.scanId,
        p_client_message_id: saved.clientMessageId,
        p_message_text: saved.messageText,
        p_displayed_ticket: saved.displayedTicket,
        p_context_version: 1,
        p_message_id: saved.messageId,
        p_conversation_id: saved.conversationId,
        p_reservation_id: saved.reservationId,
        p_lease_token: saved.leaseToken,
        p_reply: saved.reply,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) {
      if (
        Object.hasOwn(denials, error.code) &&
        denials[error.code].includes(error.message)
      ) throw new InsightChatContextAdmissionError(error.message, "rejected");
      return unknown();
    }
    const receipt = await parseInsightChatCompletion(
      data,
      saved,
      saved.conversationId,
    );
    deadline.throwIfAborted();
    if (!matches(receipt, saved.reply)) return unknown();
    return receipt;
  } catch (error) {
    if (error instanceof InsightChatContextAdmissionError) throw error;
    return unknown();
  }
}
export function completeProtectedChatReply(
  client: SupabaseClient,
  input: ProtectedChatReplyRequest,
  signal: AbortSignal,
) {
  return replyRPC(
    "complete_protected_insight_chat_reply",
    client,
    input,
    signal,
  );
}

/** Private payload equality is verified in SQL without exposing usage in the receipt. */
export function recoverProtectedChatReply(
  client: SupabaseClient,
  input: ProtectedChatReplyRequest,
  signal: AbortSignal,
) {
  return replyRPC("get_protected_insight_chat_reply", client, input, signal);
}

/** Lost replies get one exact read, never another write, grant, refund or provider call. */
export async function completeOrRecoverProtectedChatReply(
  client: SupabaseClient,
  input: ProtectedChatReplyRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const saved = request(input);
  try {
    return {
      kind: "persisted" as const,
      receipt: await completeProtectedChatReply(client, saved, signal),
    };
  } catch (error) {
    if (
      !(error instanceof InsightChatContextAdmissionError) ||
      error.transactionOutcome !== "unknown"
    ) throw error;
    signal.throwIfAborted();
    try {
      const receipt = await recoverProtectedChatReply(client, saved, signal);
      if (matches(receipt, saved.reply)) {
        return { kind: "recovered" as const, receipt };
      }
    } catch {
      signal.throwIfAborted();
    }
    throw error;
  }
}
