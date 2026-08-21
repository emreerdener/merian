import { Type } from "@google/genai";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { AIQuotaError, reserveAIProviderCall } from "../_shared/aiQuota.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { requireUuid } from "../_shared/explore.ts";
import { countAllFieldChatSendsToday } from "../_shared/fieldChatDailyUsage.ts";
import {
  fieldChatFeedbackPayload,
  fieldChatPromptSuggestionsPayload,
  fieldChatThreadPayload,
  fieldChatUserMessageForRequest,
  isFieldChatRequestComplete,
  waitForFieldChatRequestCompletion,
} from "../_shared/fieldChatResponse.ts";
import { recoverStaleFieldChatQuota } from "../_shared/fieldChatReservation.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
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
  refusalAnswer,
} from "../insight-chat/guards.ts";
import { DAILY_SEND_LIMIT, INSIGHT_CHAT_MODEL } from "../insight-chat/types.ts";
import {
  deleteConversation,
  fetchAssistantMessage,
  fetchCanonicalSpeciesContext,
  fetchConversation,
  fetchMessages,
  formatMessage,
  getOrCreateConversation,
  insertAssistantMessage,
  insertUserMessage,
  upsertFeedback,
} from "./db.ts";
import { isSpeciesDictionaryChatContextAvailable } from "./eligibility.ts";
import { buildSystemInstruction, buildUserPrompt } from "./prompt.ts";
import { buildSpeciesDictionaryChatPromptSuggestions } from "./promptSuggestions.ts";
import type {
  ModelChatResult,
  SpeciesDictionaryChatMessageRow,
} from "./types.ts";

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
    model,
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    config: {
      systemInstruction,
      temperature: 0.2,
      maxOutputTokens: 700,
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          answer: { type: Type.STRING },
          is_refusal: { type: Type.BOOLEAN },
          refusal_reason: { type: Type.STRING, nullable: true },
        },
        required: ["answer", "is_refusal", "refusal_reason"],
      },
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
  const parsed = extractJson<{
    answer?: unknown;
    is_refusal?: unknown;
    refusal_reason?: unknown;
  }>(result.text ?? "");
  return {
    answer: normalizeAssistantAnswer(
      parsed.answer,
      "I could not produce a useful answer from the Species Dictionary context.",
    ),
    isRefusal: parsed.is_refusal === true,
    refusalReason: typeof parsed.refusal_reason === "string"
      ? parsed.refusal_reason
      : null,
    usage: result.usageMetadata,
  };
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
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
    const context = await fetchCanonicalSpeciesContext(
      speciesId,
      supabaseAdmin,
    );
    if (!isSpeciesDictionaryChatContextAvailable(context)) {
      return jsonResponse({
        code: "species_not_available",
        error: "This species is not available for Field Chat.",
      }, 404);
    }

    const tier = await resolveTierForUser(user.id, supabaseAdmin);
    if (tier.effective_tier !== "pro") {
      return jsonResponse({
        code: "pro_required",
        error: "Naturebook Pro is required.",
      }, 402);
    }

    const sendsToday = await countAllFieldChatSendsToday(
      user.id,
      supabaseAdmin,
    );
    const conversation = await fetchConversation(
      user.id,
      speciesId,
      supabaseAdmin,
    );

    if (action === "delete") {
      await deleteConversation(user.id, speciesId, supabaseAdmin);
      return jsonResponse({
        data: responsePayload(speciesId, null, [], sendsToday),
      }, 200);
    }

    if (action === "load") {
      const messages = conversation
        ? await fetchMessages(conversation.id, supabaseAdmin)
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
      const message = await fetchAssistantMessage(
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
      await upsertFeedback(user.id, message, rating, note, supabaseAdmin);
      trackPostHogEvent(user, "SpeciesDictionaryChatFeedbackSubmitted", {
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
    const resolvedConversation = await getOrCreateConversation(
      user.id,
      speciesId,
      supabaseAdmin,
    );
    let beforeMessages = await fetchMessages(
      resolvedConversation.id,
      supabaseAdmin,
    );
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
            resolvedConversation.id,
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
          conversation
            ? await fetchMessages(conversation.id, supabaseAdmin)
            : [],
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
      const completion = await waitForFieldChatRequestCompletion(
        beforeMessages,
        clientMessageId,
        () => fetchMessages(resolvedConversation.id, supabaseAdmin),
      );
      if (completion) {
        return jsonResponse(
          {
            data: responsePayload(
              speciesId,
              resolvedConversation.id,
              completion,
              sendsToday,
            ),
          },
          200,
          { "X-Merian-Idempotent-Replay": "field-chat-message" },
        );
      }
      beforeMessages = await fetchMessages(
        resolvedConversation.id,
        supabaseAdmin,
      );
    }

    let quotaLease = null;
    if (!refusalReason) {
      try {
        quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
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
          const completion = await waitForFieldChatRequestCompletion(
            beforeMessages,
            clientMessageId,
            () => fetchMessages(resolvedConversation.id, supabaseAdmin),
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
                  resolvedConversation.id,
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
            await recoverStaleFieldChatQuota(supabaseAdmin, {
              userId: user.id,
              operation: "species_dictionary_chat_reply",
              requestId: clientMessageId,
              conversationId: resolvedConversation.id,
              subjectId: speciesId,
            })
          ) {
            beforeMessages = await fetchMessages(
              resolvedConversation.id,
              supabaseAdmin,
            );
            quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
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
      beforeMessages = await fetchMessages(
        resolvedConversation.id,
        supabaseAdmin,
      );
      if (isFieldChatRequestComplete(beforeMessages, clientMessageId)) {
        await quotaLease?.refund();
        return jsonResponse(
          {
            data: responsePayload(
              speciesId,
              resolvedConversation.id,
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
      ReturnType<typeof insertUserMessage>
    >["message"];
    try {
      const admission = await insertUserMessage(
        resolvedConversation.id,
        user.id,
        speciesId,
        messageText,
        clientMessageId,
        supabaseAdmin,
      );
      userMessage = admission.message;
      sendsTodayAfterRequest = admission.sendsToday;
      const admittedMessages = await fetchMessages(
        resolvedConversation.id,
        supabaseAdmin,
      );
      if (admission.isReplay) {
        if (isFieldChatRequestComplete(admittedMessages, clientMessageId)) {
          await quotaLease?.refund();
          return jsonResponse(
            {
              data: responsePayload(
                speciesId,
                resolvedConversation.id,
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
        answer: refusalAnswer(refusalReason).replaceAll(
          "saved scan",
          "Species Dictionary page",
        ),
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
        assistant = await generateAssistantReply(
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
        recordAIUsageBestEffort(supabaseAdmin, {
          operation: "species_dictionary_chat_reply",
          model: quotaLease!.reservation.model,
          effectivePlan: tier.plan,
          inputModality: "text",
          outcome: "error",
          userId: user.id,
          conversationId: resolvedConversation.id,
          sourceType: "species_dictionary",
        });
        throw error;
      }
    }

    try {
      await insertAssistantMessage(
        resolvedConversation.id,
        user.id,
        speciesId,
        clientMessageId,
        assistant,
        supabaseAdmin,
        quotaLease?.reservation.model,
      );
    } catch (error) {
      try {
        const recoveredMessages = await fetchMessages(
          resolvedConversation.id,
          supabaseAdmin,
        );
        if (isFieldChatRequestComplete(recoveredMessages, clientMessageId)) {
          return jsonResponse(
            {
              data: responsePayload(
                speciesId,
                resolvedConversation.id,
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

    const messages = await fetchMessages(
      resolvedConversation.id,
      supabaseAdmin,
    );
    recordAIUsageBestEffort(supabaseAdmin, {
      operation: "species_dictionary_chat_reply",
      model: quotaLease?.reservation.model ?? INSIGHT_CHAT_MODEL,
      usage: assistant.usage,
      effectivePlan: tier.plan,
      inputModality: "text",
      outcome: assistant.isRefusal ? "refusal" : "success",
      userId: user.id,
      conversationId: resolvedConversation.id,
      messageId: userMessage.id,
      sourceType: "species_dictionary",
    });
    trackPostHogEvent(user, "SpeciesDictionaryChatSent", {
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
        resolvedConversation.id,
        messages,
        sendsTodayAfterRequest,
      ),
    }, 200);
  })
);
