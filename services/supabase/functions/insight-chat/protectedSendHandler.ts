import type { SupabaseClient } from "@supabase/supabase-js";
import {
  jsonResponse,
  publicErrorResponse,
  PublicHttpError,
} from "../_shared/http.ts";
import { InsightChatContextAdmissionError } from "./contextAdmission.ts";
import { InsightChatContextPreflightError } from "./preparedContext.ts";
import { StoredInsightChatRecoveryError } from "./storedContextRepository.ts";
import {
  executeProtectedChatSend,
  type ProtectedChatSendDependencies,
} from "./protectedSend.ts";
import {
  parseProtectedChatSend,
  protectedChatSendPayload,
} from "./protectedSendContract.ts";
const HEADERS = { "Cache-Control": "no-store" };
/** Authenticated owner supplied by the shared edge wrapper, never a body field. */
export async function handleProtectedChatSend(
  request: Request,
  client: SupabaseClient,
  ownerId: string,
  body: unknown,
  startedAt: number,
  dependencies: ProtectedChatSendDependencies = {},
) {
  let saved;
  try {
    saved = parseProtectedChatSend(ownerId, body);
  } catch {
    return publicErrorResponse(
      request,
      400,
      "field_chat_invalid_request",
      "A complete original message and identification ticket are required.",
      { extraHeaders: HEADERS },
    );
  }
  try {
    const receipt = await executeProtectedChatSend(
      client,
      request,
      saved,
      startedAt,
      dependencies,
    );
    return jsonResponse(protectedChatSendPayload(receipt), 200, HEADERS);
  } catch (error) {
    if (error instanceof PublicHttpError) {
      return publicErrorResponse(
        request,
        error.status,
        error.code,
        error.message,
        { extraHeaders: HEADERS },
      );
    }
    if (
      error instanceof StoredInsightChatRecoveryError ||
      error instanceof InsightChatContextPreflightError
    ) {
      return publicErrorResponse(
        request,
        error.status,
        error.code,
        "The original message context could not be verified.",
        { extraHeaders: HEADERS },
      );
    }
    if (
      error instanceof InsightChatContextAdmissionError &&
      error.transactionOutcome === "rejected"
    ) {
      const statuses: Readonly<Record<string, number>> = {
        field_chat_subject_not_found: 404,
        field_chat_context_conflict: 409,
        field_chat_idempotency_conflict: 409,
        field_chat_daily_limit_reached: 429,
        field_chat_conversation_limit_reached: 409,
      };
      if (Object.hasOwn(statuses, error.code)) {
        return publicErrorResponse(
          request,
          statuses[error.code],
          error.code,
          "This message could not be completed. Preserve the original request.",
          { extraHeaders: HEADERS },
        );
      }
    }
    return publicErrorResponse(
      request,
      503,
      "field_chat_execution_held",
      "This message is awaiting recovery. Retry the same message later.",
      { extraHeaders: HEADERS },
    );
  }
}
