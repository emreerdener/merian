import type { SupabaseClient } from "@supabase/supabase-js";
import {
  admitInsightChatTurnContext,
  InsightChatContextAdmissionError,
  type InsightChatContextAdmissionRequest,
} from "./contextAdmission.ts";
import { resolveStoredInsightChatTurn } from "./storedContextRepository.ts";
import { validateStoredTurnRequest } from "./storedContext.ts";

/**
 * A single admission attempt followed only by read-only recovery on ambiguity.
 * No quota/provider transitions belong here. A rejected transaction says nothing
 * about earlier attempts; even found=false after timeout cannot prove no commit.
 */
export async function admitOrRecoverInsightChatContext(
  client: SupabaseClient,
  input: InsightChatContextAdmissionRequest,
  signal: AbortSignal,
) {
  // Freeze the retry tuple before the first await; recovery never uses a
  // caller-mutated ticket/text or invents a new conversation/request identity.
  const request = validateStoredTurnRequest({
    ownerId: input.ownerId,
    scanId: input.scanId,
    clientMessageId: input.clientMessageId,
    messageText: input.messageText,
    displayedTicket: input.displayedTicket,
  });
  try {
    const admission = await admitInsightChatTurnContext(client, input, signal);
    if (signal.aborted) {
      throw new InsightChatContextAdmissionError(
        "field_chat_context_unavailable",
        "unknown",
      );
    }
    return { kind: "admitted" as const, admission };
  } catch (error) {
    if (
      !(error instanceof InsightChatContextAdmissionError) ||
      error.transactionOutcome !== "unknown"
    ) throw error;
    if (!signal.aborted) {
      try {
        const recovered = await resolveStoredInsightChatTurn(
          client,
          request,
          signal,
        );
        if (!signal.aborted && recovered.found) {
          return { kind: "recovered" as const, recovered };
        }
      } catch {
        // Missing context, conflict, deletion, cancellation and read uncertainty
        // cannot settle an uncertain write or release its quota reservation.
      }
    }
    throw new InsightChatContextAdmissionError(
      "field_chat_context_unavailable",
      "unknown",
    );
  }
}
