import type { SupabaseClient, User } from "@supabase/supabase-js";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { AIQuotaError, reserveAIProviderCall } from "../_shared/aiQuota.ts";
import {
  type EdgeAuthenticator,
  jsonResponse,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { requireUuid } from "../_shared/explore.ts";
import {
  buildFieldChatReplyRequest,
  extractFieldChatReplyJson,
} from "../_shared/fieldChatReply.ts";
import { countAllFieldChatSendsToday } from "../_shared/fieldChatDailyUsage.ts";
import {
  fieldChatFeedbackPayload,
  fieldChatPromptSuggestionsPayload,
  fieldChatThreadPayload,
  fieldChatUserMessageForRequest,
  isFieldChatRequestComplete,
  waitForFieldChatRequestCompletion,
} from "../_shared/fieldChatResponse.ts";
import {
  fieldChatDeploymentContractHeaders,
  recoverStaleFieldChatQuota,
} from "../_shared/fieldChatReservation.ts";
import { _genAI } from "../_shared/gemini.ts";
import {
  parseJsonBody,
  publicErrorResponse,
  publicHttpError,
} from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  assertConversationHasRoom,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeAssistantAnswer,
  normalizeFeedbackNote,
  normalizeFeedbackRating,
  normalizeUserMessage,
} from "../insight-chat/guards.ts";
import { DAILY_SEND_LIMIT, INSIGHT_CHAT_MODEL } from "../insight-chat/types.ts";
import {
  deleteConversation,
  fetchAssistantMessage,
  fetchCanonicalSpeciesContext,
  fetchConversation,
  fetchMessages,
  formatMessage,
  insertAssistantMessage,
  insertUserMessage,
  upsertFeedback,
} from "./db.ts";
import { isSpeciesDictionaryChatContextAvailable } from "./eligibility.ts";
import { buildSystemInstruction, buildUserPrompt } from "./prompt.ts";
import { buildSpeciesDictionaryChatPromptSuggestions } from "./promptSuggestions.ts";
import { speciesDictionaryRefusalAnswer } from "./refusal.ts";
import type {
  ModelChatResult,
  SpeciesDictionaryChatMessageRow,
} from "./types.ts";

const FIELD_CHAT_RESPONSE_HEADERS = fieldChatDeploymentContractHeaders(
  "species-dictionary-chat",
);

export interface SpeciesDictionaryChatDependencies {
  fetchCanonicalSpeciesContext?: typeof fetchCanonicalSpeciesContext;
  resolveTierForUser?: typeof resolveTierForUser;
  countAllFieldChatSendsToday?: typeof countAllFieldChatSendsToday;
  fetchConversation?: typeof fetchConversation;
  deleteConversation?: typeof deleteConversation;
  fetchMessages?: typeof fetchMessages;
  fetchAssistantMessage?: typeof fetchAssistantMessage;
  upsertFeedback?: typeof upsertFeedback;
  trackPostHogEvent?: typeof trackPostHogEvent;
  waitForFieldChatRequestCompletion?: typeof waitForFieldChatRequestCompletion;
  reserveAIProviderCall?: typeof reserveAIProviderCall;
  recoverStaleFieldChatQuota?: typeof recoverStaleFieldChatQuota;
  insertUserMessage?: typeof insertUserMessage;
  generateAssistantReply?: typeof generateAssistantReply;
  insertAssistantMessage?: typeof insertAssistantMessage;
  recordAIUsageBestEffort?: typeof recordAIUsageBestEffort;
}

const ALLOWED_ACTIONS = new Set([
  "load",
  "send",
  "delete",
  "feedback",
  "suggest_prompts",
]);

function responsePayload(
  subjectId: string,
  conversationId: string | null,
  messages: SpeciesDictionaryChatMessageRow[],
  sendsToday: number,
) {
  return fieldChatThreadPayload(
    subjectId,
    conversationId,
    messages.map(formatMessage),
    sendsToday,
  );
}

function dictionaryFeedbackNote(value: unknown): string | null {
  const note = normalizeFeedbackNote(value);
  if (note && note.length > 500) {
    throw publicHttpError(
      400,
      "feedback_note must be 500 characters or fewer.",
    );
  }
  return note;
}

async function generateAssistantReply(
  systemInstruction: string,
  userPrompt: string,
  model = INSIGHT_CHAT_MODEL,
): Promise<ModelChatResult> {
  const result = await _genAI.models.generateContent({
    ...buildFieldChatReplyRequest(systemInstruction, userPrompt, model),
  });
  const parsed = extractFieldChatReplyJson<{
    answer?: unknown;
    is_refusal?: unknown;
    refusal_reason?: unknown;
  }>(result.text ?? "");
  return {
    answer: normalizeAssistantAnswer(
      parsed.answer,
      "I could not produce a useful answer. Please try asking again.",
    ),
    isRefusal: parsed.is_refusal === true,
    refusalReason: typeof parsed.refusal_reason === "string"
      ? parsed.refusal_reason
      : null,
    usage: result.usageMetadata,
  };
}

export async function handleSpeciesDictionaryChat(
  req: Request,
  user: User,
  supabaseAdmin: SupabaseClient,
  dependencies: SpeciesDictionaryChatDependencies = {},
): Promise<Response> {
  const loadCanonicalSpeciesContext =
    dependencies.fetchCanonicalSpeciesContext ?? fetchCanonicalSpeciesContext;
  const loadTier = dependencies.resolveTierForUser ?? resolveTierForUser;
  const loadDailyUsage = dependencies.countAllFieldChatSendsToday ??
    countAllFieldChatSendsToday;
  const loadConversation = dependencies.fetchConversation ?? fetchConversation;
  const removeConversation = dependencies.deleteConversation ??
    deleteConversation;
  const loadMessages = dependencies.fetchMessages ?? fetchMessages;
  const loadAssistantMessage = dependencies.fetchAssistantMessage ??
    fetchAssistantMessage;
  const saveFeedback = dependencies.upsertFeedback ?? upsertFeedback;
  const trackEvent = dependencies.trackPostHogEvent ?? trackPostHogEvent;
  const awaitRequestCompletion =
    dependencies.waitForFieldChatRequestCompletion ??
      waitForFieldChatRequestCompletion;
  const reserveProviderCall = dependencies.reserveAIProviderCall ??
    reserveAIProviderCall;
  const recoverProviderQuota = dependencies.recoverStaleFieldChatQuota ??
    recoverStaleFieldChatQuota;
  const admitUserMessage = dependencies.insertUserMessage ?? insertUserMessage;
  const generateReply = dependencies.generateAssistantReply ??
    generateAssistantReply;
  const saveAssistantMessage = dependencies.insertAssistantMessage ??
    insertAssistantMessage;
  const recordUsage = dependencies.recordAIUsageBestEffort ??
    recordAIUsageBestEffort;

  const body = await parseJsonBody(req, { limit: "standard" });
  if (body instanceof Response) return body;

  const action = normalizeAction(body.action);
  if (!ALLOWED_ACTIONS.has(action)) {
    return jsonResponse({
      code: "unsupported_action",
      error: "Unsupported Species Dictionary Field Chat action.",
    }, 400);
  }
  const speciesId = requireUuid(body.species_id, "species_id").toLowerCase();
  const context = await loadCanonicalSpeciesContext(
    speciesId,
    supabaseAdmin,
  );
  if (!isSpeciesDictionaryChatContextAvailable(context)) {
    return jsonResponse({
      code: "species_not_available",
      error: "This species is not available for Field Chat.",
    }, 404);
  }

  const tier = await loadTier(user.id, supabaseAdmin);
  if (tier.effective_tier !== "pro") {
    return jsonResponse({
      code: "pro_required",
      error: "Naturebook Pro is required.",
    }, 402);
  }

  const sendsToday = await loadDailyUsage(
    user.id,
    supabaseAdmin,
  );
  const conversation = await loadConversation(
    user.id,
    speciesId,
    supabaseAdmin,
  );

  if (action === "delete") {
    await removeConversation(user.id, speciesId, supabaseAdmin);
    return jsonResponse({
      data: responsePayload(speciesId, null, [], sendsToday),
    }, 200);
  }

  if (action === "load") {
    const messages = conversation
      ? await loadMessages(conversation.id, supabaseAdmin)
      : [];
    return jsonResponse({
      data: responsePayload(
        speciesId,
        conversation?.id ?? null,
        messages,
        sendsToday,
      ),
    }, 200);
  }

  if (action === "suggest_prompts") {
    return jsonResponse({
      data: fieldChatPromptSuggestionsPayload(
        speciesId,
        conversation?.id ?? null,
        buildSpeciesDictionaryChatPromptSuggestions(
          context.commonName,
          context.lookalikes.length > 0,
        ),
      ),
    }, 200);
  }

  if (action === "feedback") {
    const messageId = requireUuid(body.message_id, "message_id");
    const rating = normalizeFeedbackRating(body.feedback_rating);
    const note = dictionaryFeedbackNote(body.feedback_note);
    const message = await loadAssistantMessage(
      user.id,
      speciesId,
      messageId,
      supabaseAdmin,
    );
    if (!message) {
      return jsonResponse({
        code: "message_not_found",
        error: "Assistant message not found.",
      }, 404);
    }
    await saveFeedback(user.id, message, rating, note, supabaseAdmin);
    trackEvent(user, "SpeciesDictionaryChatFeedbackSubmitted", {
      rating,
    }).catch((error) =>
      console.error("Dictionary chat feedback telemetry failed:", error)
    );
    return jsonResponse({
      data: fieldChatFeedbackPayload(speciesId, message.id, rating),
    }, 200);
  }

  const messageText = normalizeUserMessage(body.message_text);
  const clientMessageId = requireUuid(
    body.client_message_id,
    "client_message_id",
  ).toLowerCase();
  let conversationId = conversation?.id ?? crypto.randomUUID();
  let beforeMessages = conversation
    ? await loadMessages(conversationId, supabaseAdmin)
    : [];
  const existingRequestMessage = fieldChatUserMessageForRequest(
    beforeMessages,
    clientMessageId,
  );
  const isExistingRequest = existingRequestMessage != null;
  if (
    existingRequestMessage &&
    existingRequestMessage.message_text !== messageText
  ) {
    return publicErrorResponse(
      req,
      409,
      "field_chat_idempotency_conflict",
      "This Field Chat retry key was already used for a different message.",
    );
  }
  let sendsTodayAfterRequest = sendsToday + (isExistingRequest ? 0 : 1);
  if (
    isExistingRequest &&
    isFieldChatRequestComplete(beforeMessages, clientMessageId)
  ) {
    return jsonResponse(
      {
        data: responsePayload(
          speciesId,
          conversationId,
          beforeMessages,
          sendsToday,
        ),
      },
      200,
      { "X-Merian-Idempotent-Replay": "field-chat-message" },
    );
  }

  if (!isExistingRequest && sendsToday >= DAILY_SEND_LIMIT) {
    return jsonResponse({
      code: "daily_limit_reached",
      error: "Daily Field Chat limit reached.",
      data: responsePayload(
        speciesId,
        conversation?.id ?? null,
        conversation ? await loadMessages(conversation.id, supabaseAdmin) : [],
        sendsToday,
      ),
    }, 429);
  }

  if (!isExistingRequest) {
    assertConversationHasRoom(beforeMessages.length);
  }

  const startedAt = Date.now();
  const refusalReason = isSafetyCriticalQuestion(messageText);
  if (isExistingRequest && refusalReason) {
    const completion = await awaitRequestCompletion(
      beforeMessages,
      clientMessageId,
      () => loadMessages(conversationId, supabaseAdmin),
    );
    if (completion) {
      return jsonResponse(
        {
          data: responsePayload(
            speciesId,
            conversationId,
            completion,
            sendsToday,
          ),
        },
        200,
        { "X-Merian-Idempotent-Replay": "field-chat-message" },
      );
    }
    beforeMessages = await loadMessages(
      conversationId,
      supabaseAdmin,
    );
  }

  let quotaLease = null;
  if (!refusalReason) {
    try {
      quotaLease = await reserveProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "species_dictionary_chat_reply",
        requestId: clientMessageId,
        originalAnalysisId: null,
      });
    } catch (error) {
      if (
        error instanceof AIQuotaError &&
        (
          error.code === "ai_request_already_completed" ||
          error.code === "ai_request_in_progress"
        )
      ) {
        const completion = await awaitRequestCompletion(
          beforeMessages,
          clientMessageId,
          () => loadMessages(conversationId, supabaseAdmin),
        );
        if (completion) {
          const completedRequestMessage = fieldChatUserMessageForRequest(
            completion,
            clientMessageId,
          );
          if (completedRequestMessage?.message_text !== messageText) {
            return publicErrorResponse(
              req,
              409,
              "field_chat_idempotency_conflict",
              "This Field Chat retry key was already used for a different message.",
            );
          }
          return jsonResponse(
            {
              data: responsePayload(
                speciesId,
                conversationId,
                completion,
                sendsTodayAfterRequest,
              ),
            },
            200,
            { "X-Merian-Idempotent-Replay": "field-chat-message" },
          );
        }
        if (
          error.code === "ai_request_already_completed" &&
          await recoverProviderQuota(supabaseAdmin, {
            userId: user.id,
            operation: "species_dictionary_chat_reply",
            requestId: clientMessageId,
            conversationId: conversationId,
            subjectId: speciesId,
          })
        ) {
          beforeMessages = await loadMessages(
            conversationId,
            supabaseAdmin,
          );
          quotaLease = await reserveProviderCall(req, supabaseAdmin, {
            userId: user.id,
            operation: "species_dictionary_chat_reply",
            requestId: clientMessageId,
            originalAnalysisId: null,
          });
        }
        if (quotaLease === null) {
          return publicErrorResponse(
            req,
            503,
            "field_chat_send_in_progress",
            "Your earlier Field Chat send is still completing. Please try again.",
            { retryAfterSeconds: 2 },
          );
        }
      } else {
        throw error;
      }
    }
  }

  if (isExistingRequest) {
    beforeMessages = await loadMessages(
      conversationId,
      supabaseAdmin,
    );
    if (isFieldChatRequestComplete(beforeMessages, clientMessageId)) {
      await quotaLease?.refund();
      return jsonResponse(
        {
          data: responsePayload(
            speciesId,
            conversationId,
            beforeMessages,
            sendsToday,
          ),
        },
        200,
        { "X-Merian-Idempotent-Replay": "field-chat-message" },
      );
    }
    try {
      assertConversationHasRoom(beforeMessages.length, 1);
    } catch (error) {
      await quotaLease?.refund();
      throw error;
    }
  }

  let userMessage: Awaited<
    ReturnType<typeof admitUserMessage>
  >["message"];
  try {
    const admission = await admitUserMessage(
      conversationId,
      user.id,
      speciesId,
      messageText,
      clientMessageId,
      supabaseAdmin,
    );
    conversationId = admission.conversationId;
    userMessage = admission.message;
    sendsTodayAfterRequest = admission.sendsToday;
    const admittedMessages = await loadMessages(
      conversationId,
      supabaseAdmin,
    );
    if (admission.isReplay) {
      if (isFieldChatRequestComplete(admittedMessages, clientMessageId)) {
        await quotaLease?.refund();
        return jsonResponse(
          {
            data: responsePayload(
              speciesId,
              conversationId,
              admittedMessages,
              admission.sendsToday,
            ),
          },
          200,
          { "X-Merian-Idempotent-Replay": "field-chat-message" },
        );
      }
      if (!isExistingRequest) {
        assertConversationHasRoom(admittedMessages.length, 1);
      }
    }
    beforeMessages = admittedMessages;
  } catch (error) {
    await quotaLease?.refund();
    throw error;
  }

  let assistant: ModelChatResult;
  if (refusalReason) {
    assistant = {
      answer: speciesDictionaryRefusalAnswer(refusalReason),
      isRefusal: true,
      refusalReason,
      usage: null,
    };
  } else {
    let providerAttempted = false;
    try {
      const systemInstruction = buildSystemInstruction(context);
      const userPrompt = buildUserPrompt(
        beforeMessages.filter((message) =>
          message.role !== "user" ||
          message.client_message_id !== clientMessageId
        ),
        messageText,
      );
      await quotaLease!.commit();
      providerAttempted = true;
      assistant = await generateReply(
        systemInstruction,
        userPrompt,
        quotaLease!.reservation.model,
      );
    } catch (error) {
      if (providerAttempted) {
        await quotaLease!.fail();
      } else {
        await quotaLease!.refund();
      }
      recordUsage(supabaseAdmin, {
        operation: "species_dictionary_chat_reply",
        model: quotaLease!.reservation.model,
        effectivePlan: tier.plan,
        inputModality: "text",
        outcome: "error",
        userId: user.id,
        conversationId: conversationId,
        sourceType: "species_dictionary",
      });
      throw error;
    }
  }

  try {
    await saveAssistantMessage(
      conversationId,
      user.id,
      speciesId,
      clientMessageId,
      assistant,
      supabaseAdmin,
      quotaLease?.reservation.model,
    );
  } catch (error) {
    try {
      const recoveredMessages = await loadMessages(
        conversationId,
        supabaseAdmin,
      );
      if (isFieldChatRequestComplete(recoveredMessages, clientMessageId)) {
        return jsonResponse(
          {
            data: responsePayload(
              speciesId,
              conversationId,
              recoveredMessages,
              sendsTodayAfterRequest,
            ),
          },
          200,
          { "X-Merian-Idempotent-Replay": "field-chat-message" },
        );
      }
    } catch {
      // Preserve the original persistence error. The same request remains
      // eligible for exact-row-bound stale recovery when applicable.
    }
    await quotaLease?.fail();
    throw error;
  }

  const messages = await loadMessages(
    conversationId,
    supabaseAdmin,
  );
  recordUsage(supabaseAdmin, {
    operation: "species_dictionary_chat_reply",
    model: quotaLease?.reservation.model ?? INSIGHT_CHAT_MODEL,
    usage: assistant.usage,
    effectivePlan: tier.plan,
    inputModality: "text",
    outcome: assistant.isRefusal ? "refusal" : "success",
    userId: user.id,
    conversationId: conversationId,
    messageId: userMessage.id,
    sourceType: "species_dictionary",
  });
  trackEvent(user, "SpeciesDictionaryChatSent", {
    message_length: messageText.length,
    is_refusal: assistant.isRefusal,
    latency_ms: Date.now() - startedAt,
    plan: tier.plan,
  }).catch((error) =>
    console.error("Dictionary chat telemetry failed:", error)
  );

  return jsonResponse({
    data: responsePayload(
      speciesId,
      conversationId,
      messages,
      sendsTodayAfterRequest,
    ),
  }, 200);
}

export function createSpeciesDictionaryChatHttpHandler(
  dependencies: SpeciesDictionaryChatDependencies = {},
  options: { authenticate?: EdgeAuthenticator } = {},
): (req: Request) => Promise<Response> {
  return (req: Request) =>
    withEdgeHandler(
      req,
      (user, supabaseAdmin) =>
        handleSpeciesDictionaryChat(
          req,
          user,
          supabaseAdmin,
          dependencies,
        ),
      {
        ...options,
        responseHeaders: FIELD_CHAT_RESPONSE_HEADERS,
      },
    );
}

if (import.meta.main) {
  Deno.serve((req: Request) =>
    withEdgeHandler(
      req,
      (user, supabaseAdmin) =>
        handleSpeciesDictionaryChat(req, user, supabaseAdmin),
      { responseHeaders: FIELD_CHAT_RESPONSE_HEADERS },
    )
  );
}
