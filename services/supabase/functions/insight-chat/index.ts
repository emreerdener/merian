import { Type } from "@google/genai";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { requireUuid } from "../_shared/explore.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { AIQuotaError, reserveAIProviderCall } from "../_shared/aiQuota.ts";
import {
  fieldChatFeatureFeedbackPayload,
  fieldChatFeedbackPayload,
  fieldChatPromptSuggestionsPayload,
  fieldChatSummaryPayload,
  fieldChatThreadPayload,
  fieldChatUserMessageForRequest,
  isFieldChatRequestComplete,
  waitForFieldChatRequestCompletion,
} from "../_shared/fieldChatResponse.ts";
import { recoverStaleFieldChatQuota } from "../_shared/fieldChatReservation.ts";
import {
  countUserSendsToday,
  deleteConversation,
  fetchConversation,
  fetchMessages,
  fetchOwnedAssistantMessage,
  fetchOwnedScan,
  formatMessage,
  getOrCreateConversation,
  insertAssistantMessage,
  insertFeatureFeedback,
  insertUserMessage,
  upsertMessageFeedback,
} from "./db.ts";
import {
  assertConversationHasRoom,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeAssistantAnswer,
  normalizeFeatureFeedbackSentiment,
  normalizeFeedbackNote,
  normalizeFeedbackRating,
  normalizeUserMessage,
  refusalAnswer,
} from "./guards.ts";
import {
  buildPromptSuggestionsPrompt,
  buildSystemInstruction,
  buildUserPrompt,
  sanitizeFieldNotesDraft,
} from "./prompt.ts";
import { sanitizePromptSuggestions } from "./promptSuggestions.ts";
import {
  DAILY_SEND_LIMIT,
  INSIGHT_CHAT_MODEL,
  InsightChatMessageRow,
  InsightChatPromptSuggestionPayload,
  InsightChatResponsePayload,
  ModelChatResult,
} from "./types.ts";

function responsePayload(
  subjectId: string,
  conversationId: string | null,
  messages: InsightChatMessageRow[],
  sendsToday: number,
): InsightChatResponsePayload {
  return fieldChatThreadPayload(
    subjectId,
    conversationId,
    messages.map(formatMessage),
    sendsToday,
  );
}

function messageCategory(text: string): string {
  const normalized = text.toLowerCase();
  if (normalized.includes("tell it apart") || normalized.includes("compare")) {
    return "lookalike_compare";
  }
  if (normalized.includes("risk") || normalized.includes("hazard")) {
    return "hazard";
  }
  if (normalized.includes("invasive")) return "invasive";
  if (normalized.includes("trait") || normalized.includes("support this id")) {
    return "evidence";
  }
  if (normalized.includes("habitat")) return "habitat";
  if (normalized.includes("typical in") || normalized.includes("season")) {
    return "season";
  }
  if (normalized.includes("strong match") || normalized.includes("uncertain")) {
    return "confidence";
  }
  return "generic";
}

async function generateAssistantReply(
  systemInstruction: string,
  userPrompt: string,
  model = INSIGHT_CHAT_MODEL,
): Promise<ModelChatResult> {
  const responseSchema = {
    type: Type.OBJECT,
    properties: {
      answer: { type: Type.STRING },
      is_refusal: { type: Type.BOOLEAN },
      refusal_reason: { type: Type.STRING, nullable: true },
    },
    required: ["answer", "is_refusal", "refusal_reason"],
  };

  const result = await _genAI.models.generateContent({
    model,
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    config: {
      systemInstruction,
      temperature: 0.2,
      maxOutputTokens: 700,
      responseMimeType: "application/json",
      responseSchema,
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
      "I could not produce a useful answer from the saved scan context.",
    ),
    isRefusal: parsed.is_refusal === true,
    refusalReason: typeof parsed.refusal_reason === "string"
      ? parsed.refusal_reason
      : null,
    usage: result.usageMetadata,
  };
}

async function generateFieldNotesSummary(
  systemInstruction: string,
  messages: InsightChatMessageRow[],
  model = INSIGHT_CHAT_MODEL,
): Promise<{
  summaryText: string;
  usage: ModelChatResult["usage"];
}> {
  const responseSchema = {
    type: Type.OBJECT,
    properties: {
      summary_text: { type: Type.STRING },
    },
    required: ["summary_text"],
  };
  const userPrompt = `${
    buildUserPrompt(messages, "Summarize this chat into private field notes.")
  }

[FIELD NOTES DRAFT REQUEST]
Create a concise, factual field-notes draft from the saved scan context and chat.
Use only observation-relevant details. Refer to the observation by common name,
scientific name, or "this observation"; never include scan ids, UUIDs, storage
ids, or other internal identifiers. Do not replace existing notes. Do not add
medical, edible, legal, pesticide, or exact-location instructions.`;

  const result = await _genAI.models.generateContent({
    model,
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    config: {
      systemInstruction,
      temperature: 0.15,
      maxOutputTokens: 450,
      responseMimeType: "application/json",
      responseSchema,
      thinkingConfig: { thinkingBudget: 0 },
    },
  });

  const parsed = extractJson<{ summary_text?: unknown }>(result.text ?? "");
  const rawSummaryText = typeof parsed.summary_text === "string" &&
      parsed.summary_text.trim()
    ? parsed.summary_text.trim()
    : "";
  const summaryText = sanitizeFieldNotesDraft(rawSummaryText);
  return { summaryText, usage: result.usageMetadata };
}

async function generatePromptSuggestions(
  systemInstruction: string,
  messages: InsightChatMessageRow[],
  model = INSIGHT_CHAT_MODEL,
): Promise<{
  prompts: InsightChatPromptSuggestionPayload[];
  usage: ModelChatResult["usage"];
}> {
  const responseSchema = {
    type: Type.OBJECT,
    properties: {
      prompts: {
        type: Type.ARRAY,
        items: {
          type: Type.OBJECT,
          properties: {
            text: { type: Type.STRING },
            category: { type: Type.STRING },
          },
          required: ["text", "category"],
        },
      },
    },
    required: ["prompts"],
  };

  const result = await _genAI.models.generateContent({
    model,
    contents: [{
      role: "user",
      parts: [{ text: buildPromptSuggestionsPrompt(messages) }],
    }],
    config: {
      systemInstruction,
      temperature: 0.45,
      maxOutputTokens: 220,
      responseMimeType: "application/json",
      responseSchema,
      thinkingConfig: { thinkingBudget: 0 },
    },
  });

  const parsed = extractJson<{ prompts?: unknown }>(result.text ?? "");
  return {
    prompts: sanitizePromptSuggestions(parsed.prompts),
    usage: result.usageMetadata,
  };
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
    if (parsedBody instanceof Response) return parsedBody;

    const action = normalizeAction(parsedBody.action);
    const scanId = requireUuid(parsedBody.scan_id, "scan_id").toLowerCase();
    const sendsToday = await countUserSendsToday(user.id, supabaseAdmin);

    const scan = await fetchOwnedScan(user.id, scanId, supabaseAdmin);
    if (!scan) {
      return jsonResponse({
        code: "scan_not_ready",
        error: "Scan not ready for chat.",
      }, 404);
    }

    if (scan.is_biological_subject === false) {
      return jsonResponse({
        code: "unsupported_scan",
        error: "Insight chat is available for biological scans.",
      }, 400);
    }

    const tier = await resolveTierForUser(user.id, supabaseAdmin);
    if (tier.effective_tier !== "pro") {
      trackPostHogEvent(user, "InsightChatRateLimited", {
        reason: "pro_required",
        scan_id: scanId,
      }).catch((e) =>
        console.error("PostHog InsightChatRateLimited failed:", e)
      );
      return jsonResponse({
        code: "pro_required",
        error: "Insight chat requires Naturebook Pro.",
      }, 402);
    }

    if (action === "delete") {
      await deleteConversation(user.id, scanId, supabaseAdmin);
      return jsonResponse({
        data: responsePayload(scanId, null, [], sendsToday),
      }, 200);
    }

    const existingConversation = await fetchConversation(
      user.id,
      scanId,
      supabaseAdmin,
    );
    if (action === "load") {
      const messages = existingConversation
        ? await fetchMessages(existingConversation.id, supabaseAdmin)
        : [];
      return jsonResponse({
        data: responsePayload(
          scanId,
          existingConversation?.id ?? null,
          messages,
          sendsToday,
        ),
      }, 200);
    }

    if (action === "suggest_prompts") {
      const messages = existingConversation
        ? await fetchMessages(existingConversation.id, supabaseAdmin)
        : [];
      const startedAt = Date.now();
      const quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "insight_chat_prompt_suggestions",
        requestId: parsedBody.ai_request_id,
      });

      let providerAttempted = false;
      try {
        const systemInstruction = buildSystemInstruction(scan);
        await quotaLease.commit();
        providerAttempted = true;
        const suggestions = await generatePromptSuggestions(
          systemInstruction,
          messages,
          quotaLease.reservation.model,
        );
        const usage = suggestions.usage;
        recordAIUsageBestEffort(supabaseAdmin, {
          operation: "insight_chat_prompt_suggestions",
          model: quotaLease.reservation.model,
          usage,
          effectivePlan: tier.plan,
          inputModality: "text",
          userId: user.id,
          scanId,
          conversationId: existingConversation?.id ?? null,
        });
        trackPostHogEvent(user, "InsightChatPromptsGenerated", {
          scan_id: scanId,
          conversation_id: existingConversation?.id ?? null,
          prompt_categories: suggestions.prompts.map((prompt) =>
            prompt.category
          ),
          prompt_count: suggestions.prompts.length,
          fallback_state: suggestions.prompts.length === 3
            ? "model"
            : "partial_model",
          latency_ms: Date.now() - startedAt,
          llm_model: quotaLease.reservation.model,
          llm_prompt_tokens: usage?.promptTokenCount ?? null,
          llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
          llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
          llm_total_tokens: usage?.totalTokenCount ?? null,
          llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
        }).catch((e) =>
          console.error("PostHog InsightChatPromptsGenerated failed:", e)
        );

        return jsonResponse({
          data: fieldChatPromptSuggestionsPayload(
            scanId,
            existingConversation?.id ?? null,
            suggestions.prompts,
          ),
        }, 200);
      } catch (error) {
        if (providerAttempted) {
          await quotaLease.fail();
        } else {
          await quotaLease.refund();
        }
        trackPostHogEvent(user, "InsightChatPromptsGenerated", {
          scan_id: scanId,
          conversation_id: existingConversation?.id ?? null,
          prompt_categories: [],
          prompt_count: 0,
          fallback_state: "model_error",
          latency_ms: Date.now() - startedAt,
          llm_model: quotaLease.reservation.model,
          error: error instanceof Error ? error.message : String(error),
        }).catch((e) =>
          console.error("PostHog InsightChatPromptsGenerated failed:", e)
        );
        return publicErrorResponse(
          req,
          502,
          "prompt_suggestions_unavailable",
          "Prompt suggestions are unavailable right now.",
        );
      }
    }

    if (action === "feedback") {
      const messageId = requireUuid(parsedBody.message_id, "message_id");
      const rating = normalizeFeedbackRating(parsedBody.feedback_rating);
      const note = normalizeFeedbackNote(parsedBody.feedback_note);
      const message = await fetchOwnedAssistantMessage(
        user.id,
        scanId,
        messageId,
        supabaseAdmin,
      );
      if (!message) {
        return jsonResponse({
          code: "message_not_found",
          error: "Assistant message not found.",
        }, 404);
      }

      await upsertMessageFeedback(
        user.id,
        message,
        rating,
        note,
        supabaseAdmin,
      );
      trackPostHogEvent(user, "InsightChatFeedbackSubmitted", {
        scan_id: scanId,
        conversation_id: message.conversation_id,
        message_id: message.id,
        rating,
        is_refusal: message.is_refusal,
        refusal_reason: message.refusal_reason,
      }).catch((e) =>
        console.error("PostHog InsightChatFeedbackSubmitted failed:", e)
      );
      return jsonResponse({
        data: fieldChatFeedbackPayload(
          scanId,
          message.id,
          rating,
        ),
      }, 200);
    }

    if (action === "feature_feedback") {
      const sentiment = normalizeFeatureFeedbackSentiment(
        parsedBody.feature_feedback_sentiment,
      );
      const note = normalizeFeedbackNote(parsedBody.feedback_note);
      if (!sentiment && !note) {
        return jsonResponse({
          code: "feature_feedback_empty",
          error: "Feature feedback requires a rating or note.",
        }, 400);
      }

      const saved = await insertFeatureFeedback(
        user.id,
        scanId,
        existingConversation?.id ?? null,
        sentiment,
        note,
        supabaseAdmin,
      );
      trackPostHogEvent(user, "InsightChatFeatureFeedbackSubmitted", {
        scan_id: scanId,
        conversation_id: existingConversation?.id ?? null,
        sentiment,
        has_note: note != null,
      }).catch((e) =>
        console.error("PostHog InsightChatFeatureFeedbackSubmitted failed:", e)
      );
      return jsonResponse({
        data: fieldChatFeatureFeedbackPayload(
          scanId,
          saved.id,
          saved.sentiment,
        ),
      }, 200);
    }

    if (action === "summarize_notes") {
      if (!existingConversation) {
        return jsonResponse({
          code: "conversation_not_found",
          error: "No chat messages to summarize.",
        }, 404);
      }
      const messages = await fetchMessages(
        existingConversation.id,
        supabaseAdmin,
      );
      if (messages.length === 0) {
        return jsonResponse({
          code: "conversation_empty",
          error: "No chat messages to summarize.",
        }, 400);
      }
      const startedAt = Date.now();
      const quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "insight_chat_summary",
        requestId: parsedBody.ai_request_id,
      });
      let summary: Awaited<ReturnType<typeof generateFieldNotesSummary>>;
      let providerAttempted = false;
      try {
        const systemInstruction = buildSystemInstruction(scan);
        await quotaLease.commit();
        providerAttempted = true;
        summary = await generateFieldNotesSummary(
          systemInstruction,
          messages,
          quotaLease.reservation.model,
        );
      } catch (error) {
        if (providerAttempted) {
          await quotaLease.fail();
        } else {
          await quotaLease.refund();
        }
        throw error;
      }
      const usage = summary.usage;
      recordAIUsageBestEffort(supabaseAdmin, {
        operation: "insight_chat_summary",
        model: quotaLease.reservation.model,
        usage,
        effectivePlan: tier.plan,
        inputModality: "text",
        userId: user.id,
        scanId,
        conversationId: existingConversation.id,
      });
      trackPostHogEvent(user, "InsightChatNotesSummarized", {
        scan_id: scanId,
        conversation_id: existingConversation.id,
        message_count: messages.length,
        latency_ms: Date.now() - startedAt,
        llm_model: quotaLease.reservation.model,
        llm_prompt_tokens: usage?.promptTokenCount ?? null,
        llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
        llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
        llm_total_tokens: usage?.totalTokenCount ?? null,
        llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
      }).catch((e) =>
        console.error("PostHog InsightChatNotesSummarized failed:", e)
      );
      return jsonResponse({
        data: fieldChatSummaryPayload(scanId, summary.summaryText),
      }, 200);
    }

    const messageText = normalizeUserMessage(parsedBody.message_text);
    const clientMessageId = requireUuid(
      parsedBody.client_message_id,
      "client_message_id",
    ).toLowerCase();

    const resolvedConversation = await getOrCreateConversation(
      user.id,
      scanId,
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
            scanId,
            resolvedConversation.id,
            beforeMessages,
            sendsToday,
          ),
        },
        200,
        {
          "X-Merian-Idempotent-Replay": "field-chat-message",
        },
      );
    }

    if (!isExistingRequest && sendsToday >= DAILY_SEND_LIMIT) {
      trackPostHogEvent(user, "InsightChatRateLimited", {
        reason: "daily_limit",
        scan_id: scanId,
        daily_send_limit: DAILY_SEND_LIMIT,
      }).catch((e) =>
        console.error("PostHog InsightChatRateLimited failed:", e)
      );
      return jsonResponse({
        code: "daily_limit_reached",
        error: "Daily Insight chat limit reached.",
        data: responsePayload(
          scanId,
          existingConversation?.id ?? null,
          existingConversation
            ? await fetchMessages(existingConversation.id, supabaseAdmin)
            : [],
          sendsToday,
        ),
      }, 429);
    }

    if (!isExistingRequest) {
      assertConversationHasRoom(beforeMessages.length);
    }

    const startedAt = Date.now();
    let assistantResult: ModelChatResult;
    const localRefusalReason = isSafetyCriticalQuestion(messageText);
    if (isExistingRequest && localRefusalReason) {
      const completion = await waitForFieldChatRequestCompletion(
        beforeMessages,
        clientMessageId,
        () => fetchMessages(resolvedConversation.id, supabaseAdmin),
      );
      if (completion) {
        return jsonResponse(
          {
            data: responsePayload(
              scanId,
              resolvedConversation.id,
              completion,
              sendsToday,
            ),
          },
          200,
          {
            "X-Merian-Idempotent-Replay": "field-chat-message",
          },
        );
      }
      beforeMessages = await fetchMessages(
        resolvedConversation.id,
        supabaseAdmin,
      );
    }

    let quotaLease = null;
    if (!localRefusalReason) {
      try {
        quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
          userId: user.id,
          operation: "insight_chat_reply",
          requestId: clientMessageId,
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
                  scanId,
                  resolvedConversation.id,
                  completion,
                  sendsTodayAfterRequest,
                ),
              },
              200,
              {
                "X-Merian-Idempotent-Replay": "field-chat-message",
              },
            );
          }
          if (
            error.code === "ai_request_already_completed" &&
            await recoverStaleFieldChatQuota(supabaseAdmin, {
              userId: user.id,
              operation: "insight_chat_reply",
              requestId: clientMessageId,
              conversationId: resolvedConversation.id,
              subjectId: scanId,
            })
          ) {
            beforeMessages = await fetchMessages(
              resolvedConversation.id,
              supabaseAdmin,
            );
            quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
              userId: user.id,
              operation: "insight_chat_reply",
              requestId: clientMessageId,
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
        }
        throw error;
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
              scanId,
              resolvedConversation.id,
              beforeMessages,
              sendsToday,
            ),
          },
          200,
          {
            "X-Merian-Idempotent-Replay": "field-chat-message",
          },
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
        scanId,
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
                scanId,
                resolvedConversation.id,
                admittedMessages,
                admission.sendsToday,
              ),
            },
            200,
            {
              "X-Merian-Idempotent-Replay": "field-chat-message",
            },
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

    if (localRefusalReason) {
      assistantResult = {
        answer: refusalAnswer(localRefusalReason),
        isRefusal: true,
        refusalReason: localRefusalReason,
        usage: null,
      };
    } else {
      let providerAttempted = false;
      try {
        const systemInstruction = buildSystemInstruction(scan);
        const userPrompt = buildUserPrompt(
          beforeMessages.filter((message) =>
            message.role !== "user" ||
            message.client_message_id !== clientMessageId
          ),
          messageText,
        );
        await quotaLease!.commit();
        providerAttempted = true;
        assistantResult = await generateAssistantReply(
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
          operation: "insight_chat_reply",
          model: quotaLease!.reservation.model,
          effectivePlan: tier.plan,
          inputModality: "text",
          outcome: "error",
          userId: user.id,
          scanId,
          conversationId: resolvedConversation.id,
        });
        trackPostHogEvent(user, "InsightChatModelError", {
          scan_id: scanId,
          conversation_id: resolvedConversation.id,
          error: error instanceof Error ? error.message : String(error),
        }).catch((e) =>
          console.error("PostHog InsightChatModelError failed:", e)
        );
        throw error;
      }
    }

    try {
      await insertAssistantMessage(
        resolvedConversation.id,
        user.id,
        scanId,
        clientMessageId,
        assistantResult,
        supabaseAdmin,
        quotaLease?.reservation.model,
      );
    } catch (error) {
      try {
        const recoveredMessages = await fetchMessages(
          resolvedConversation.id,
          supabaseAdmin,
        );
        if (
          isFieldChatRequestComplete(recoveredMessages, clientMessageId)
        ) {
          return jsonResponse(
            {
              data: responsePayload(
                scanId,
                resolvedConversation.id,
                recoveredMessages,
                sendsTodayAfterRequest,
              ),
            },
            200,
            {
              "X-Merian-Idempotent-Replay": "field-chat-message",
            },
          );
        }
      } catch {
        // Preserve the original persistence error. A failed quota transition
        // below makes the same request id eligible for a metered retry.
      }
      await quotaLease?.fail();
      throw error;
    }

    const messages = await fetchMessages(
      resolvedConversation.id,
      supabaseAdmin,
    );
    const usage = assistantResult.usage;
    const telemetry = {
      scan_id: scanId,
      conversation_id: resolvedConversation.id,
      user_message_id: userMessage.id,
      answer_category: messageCategory(messageText),
      llm_model: assistantResult.usage
        ? quotaLease?.reservation.model ?? null
        : null,
      latency_ms: Date.now() - startedAt,
      llm_prompt_tokens: usage?.promptTokenCount ?? null,
      llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
      llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
      llm_total_tokens: usage?.totalTokenCount ?? null,
      llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
      is_refusal: assistantResult.isRefusal,
      refusal_reason: assistantResult.refusalReason,
      message_count: messages.length,
      plan: tier.plan,
    };

    trackPostHogEvent(user, "InsightChatSent", {
      scan_id: scanId,
      conversation_id: resolvedConversation.id,
      message_length: messageText.length,
      answer_category: messageCategory(messageText),
      plan: tier.plan,
    }).catch((e) => console.error("PostHog InsightChatSent failed:", e));

    trackPostHogEvent(
      user,
      assistantResult.isRefusal ? "InsightChatRefused" : "InsightChatAnswered",
      telemetry,
    )
      .catch((e) => console.error("PostHog InsightChatAnswered failed:", e));

    return jsonResponse({
      data: responsePayload(
        scanId,
        resolvedConversation.id,
        messages,
        sendsTodayAfterRequest,
      ),
    }, 200);
  })
);
