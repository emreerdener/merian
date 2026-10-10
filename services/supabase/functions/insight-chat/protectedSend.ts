import type { SupabaseClient } from "@supabase/supabase-js";
import { quotaIpHash } from "../_shared/aiQuota.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { publicHttpError } from "../_shared/http.ts";
import { InsightChatContextAdmissionError } from "./contextAdmission.ts";
import {
  admitInsightChatLocalRefusal,
  LOCAL_REFUSAL_REASONS,
  readInsightChatCompletion,
} from "./exactCompletion.ts";
import { isSafetyCriticalQuestion } from "./guards.ts";
import {
  buildImmutableChatSystemInstruction,
  buildImmutableChatUserPrompt,
  immutableChatSemantics,
} from "./immutableContextPrompt.ts";
import { readChatNoAdmission, sealChatNoAdmission } from "./noAdmission.ts";
import {
  InsightChatContextPreflightError,
  prepareInsightChatSendContext,
} from "./preparedContext.ts";
import { admitOrRecoverProtectedInsightChatContext } from "./protectedContextAdmission.ts";
import {
  grantProtectedChatDispatch,
  reserveProtectedChatQuota,
} from "./protectedExecution.ts";
import {
  prepareProtectedChatProvider,
  PROTECTED_CHAT_PROVIDER_MS,
} from "./protectedProvider.ts";
import { completeOrRecoverProtectedChatReply } from "./protectedReply.ts";
import type { ProtectedChatSend } from "./protectedSendContract.ts";
import { resolveStoredInsightChatTurn } from "./storedContextRepository.ts";

export const PROTECTED_CHAT_REQUEST_MS = 135_000;
const PERSISTENCE_RESERVE_MS = 15_000;
const GRANT_MS = 5_000;
const DISPATCH_MARGIN_MS = 2_000;
function held(): never {
  throw publicHttpError(
    503,
    "This message is awaiting recovery. Retry the same message later.",
    "field_chat_execution_held",
  );
}
export interface ProtectedChatSendDependencies {
  now?: () => number;
  tier?: typeof resolveTierForUser;
  ipHash?: typeof quotaIpHash;
  provider?: typeof prepareProtectedChatProvider;
}
/** Recovery never grants execution. Fresh one-time dispatch is the sole provider path. */
export async function executeProtectedChatSend(
  client: SupabaseClient,
  request: Request,
  saved: ProtectedChatSend,
  startedAt: number,
  dependencies: ProtectedChatSendDependencies = {},
) {
  const now = dependencies.now ?? (() => performance.now());
  const remaining = () => PROTECTED_CHAT_REQUEST_MS - (now() - startedAt);
  if (remaining() <= 0) return held();
  const signal = AbortSignal.any([
    request.signal,
    AbortSignal.timeout(Math.ceil(remaining())),
  ]);
  const turn = saved.turn;
  async function completion(message: { id: string; conversation_id: string }) {
    const result = await readInsightChatCompletion(client, {
      ...turn,
      messageId: message.id,
      conversationId: message.conversation_id,
    }, signal);
    if (!result.completed) return held();
    return result;
  }
  const recovered = await resolveStoredInsightChatTurn(client, turn, signal);
  if (recovered.found) return await completion(recovered.message);
  const sealed = await readChatNoAdmission(client, saved, signal);
  if (sealed.status === "not_admitted") return sealed;
  if (sealed.status !== "fresh_candidate") return held();
  const prepared = await prepareInsightChatSendContext(client, {
    ownerId: turn.ownerId,
    scanId: turn.scanId,
    displayedTicket: turn.displayedTicket,
  }, signal).catch(async (error: unknown) => {
    if (
      !(error instanceof InsightChatContextPreflightError) ||
      error.code !== "field_chat_context_conflict" || error.status !== 409
    ) throw error;
    const proof = await sealChatNoAdmission(client, saved, signal);
    if (proof.status !== "not_admitted") return held();
    return proof;
  });
  if ("status" in prepared) return prepared;
  if (!immutableChatSemantics(prepared).eligible) {
    throw publicHttpError(
      400,
      "Field Chat is unavailable for this identification.",
      "unsupported_scan",
    );
  }
  const tier = await (dependencies.tier ?? resolveTierForUser)(
    turn.ownerId,
    client,
    signal,
  );
  signal.throwIfAborted();
  if (tier.effective_tier !== "pro") {
    throw publicHttpError(
      402,
      "Field Chat requires Naturebook Pro.",
      "pro_required",
    );
  }
  const safety = isSafetyCriticalQuestion(turn.messageText);
  if (safety !== null) {
    const reason = LOCAL_REFUSAL_REASONS.find((value) => value === safety);
    if (!reason) return held();
    try {
      return await admitInsightChatLocalRefusal(client, {
        ...turn,
        conversationId: saved.conversationId,
        reason,
      }, signal);
    } catch (error) {
      if (
        !(error instanceof InsightChatContextAdmissionError) ||
        error.transactionOutcome !== "unknown"
      ) throw error;
      // A missing read cannot disprove a still-committing original transaction.
      const original = await resolveStoredInsightChatTurn(client, turn, signal);
      if (!original.found) return held();
      return await completion(original.message);
    }
  }
  // Do not reserve work when the maximum provider and persistence budget cannot fit.
  if (
    remaining() <
      PROTECTED_CHAT_PROVIDER_MS + PERSISTENCE_RESERVE_MS + GRANT_MS +
        DISPATCH_MARGIN_MS + 10_000
  ) return held();
  const ip = await (dependencies.ipHash ?? quotaIpHash)(request);
  signal.throwIfAborted();
  const quota = await reserveProtectedChatQuota(client, turn, ip, signal);
  if (quota.status !== "reserved") return held();
  const outcome = await admitOrRecoverProtectedInsightChatContext(client, {
    ...turn,
    conversationId: saved.conversationId,
    reservationId: quota.reservationId,
    leaseToken: quota.leaseToken,
  }, signal);
  if (outcome.kind === "recovered") {
    return await completion(outcome.recovered.message);
  }
  if (outcome.kind !== "admitted" || outcome.admission.isReplay) {
    return await completion(outcome.admission.message);
  }
  const admitted = outcome.admission;
  const invoke = (dependencies.provider ?? prepareProtectedChatProvider)(
    buildImmutableChatSystemInstruction(admitted.context),
    buildImmutableChatUserPrompt(admitted.context, turn.messageText),
    quota.model,
  );
  if (
    remaining() <
      PROTECTED_CHAT_PROVIDER_MS + PERSISTENCE_RESERVE_MS + GRANT_MS +
        DISPATCH_MARGIN_MS
  ) return held();
  signal.throwIfAborted();
  const grant = await grantProtectedChatDispatch(client, {
    ownerId: turn.ownerId,
    scanId: turn.scanId,
    clientMessageId: turn.clientMessageId,
    reservationId: quota.reservationId,
    leaseToken: quota.leaseToken,
  }, signal);
  if (grant.status !== "dispatch_granted" || grant.model !== quota.model) {
    return held();
  }
  // Once granted, invoke exactly once. Bound any scheduler/grant overrun to the
  // remaining provider window while preserving persistence time.
  const providerSignal = AbortSignal.any([
    signal,
    AbortSignal.timeout(
      Math.max(1, Math.floor(remaining() - PERSISTENCE_RESERVE_MS)),
    ),
  ]);
  const reply = await invoke(providerSignal);
  signal.throwIfAborted();
  const result = await completeOrRecoverProtectedChatReply(client, {
    ...turn,
    messageId: admitted.message.id,
    conversationId: admitted.conversationId,
    reservationId: quota.reservationId,
    leaseToken: quota.leaseToken,
    reply,
  }, signal);
  if (!result.receipt.completed) return held();
  return result.receipt;
}
