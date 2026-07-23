import { Type } from "@google/genai";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { requireUuid } from "../_shared/explore.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { reserveAIProviderCall } from "../_shared/aiQuota.ts";
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
import {
  DAILY_SEND_LIMIT,
  INSIGHT_CHAT_MODEL,
  InsightChatMessageRow,
  InsightChatPromptSuggestionPayload,
  InsightChatResponsePayload,
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
  ModelChatResult,
} from "./types.ts";

const PROMPT_CATEGORY_ALLOWLIST = new Set([
  "lookalike_compare",
  "hazard",
  "invasive",
  "evidence",
  "habitat",
  "season",
  "confidence",
  "ecology",
  "field_notes",
  "generic",
]);

function limitsPayload(sendsToday: number) {
  return {
    max_user_message_chars: MAX_USER_MESSAGE_CHARS,
    max_messages_per_conversation: MAX_MESSAGES_PER_CONVERSATION,
    daily_send_limit: DAILY_SEND_LIMIT,
    sends_remaining_today: Math.max(0, DAILY_SEND_LIMIT - sendsToday),
  };
}

function responsePayload(
  conversationId: string | null,
  messages: InsightChatMessageRow[],
  sendsToday: number,
): InsightChatResponsePayload {
  return {
    conversation_id: conversationId,
    messages: messages.map(formatMessage),
    limits: limitsPayload(sendsToday),
  };
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

  const answer = typeof parsed.answer === "string" && parsed.answer.trim()
    ? parsed.answer.trim()
    : "I could not produce a useful answer from the saved scan context.";

  return {
    answer,
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
    : "Field chat discussed the saved observation and follow-up identification context.";
  const summaryText = sanitizeFieldNotesDraft(rawSummaryText);
  return { summaryText, usage: result.usageMetadata };
}

function sanitizePromptSuggestions(
  prompts: unknown,
): InsightChatPromptSuggestionPayload[] {
  if (!Array.isArray(prompts)) return [];

  const seen = new Set<string>();
  const safePattern =
    /\b(eat|edible|taste|cook|bake|brew|tea|forag|feed|consume|treat|treatment|dosage|medicine|medical|veterinary|pesticide|poison|kill|exterminate|trap|capture|handle|pick up|relocate|collect|harvest|permit|gps|coordinates|latitude|longitude|person|human)\b/i;
  const suggestions: InsightChatPromptSuggestionPayload[] = [];

  for (const prompt of prompts) {
    if (!prompt || typeof prompt !== "object") continue;
    const rawText = "text" in prompt ? prompt.text : null;
    const rawCategory = "category" in prompt ? prompt.category : null;
    if (typeof rawText !== "string") continue;

    const text = rawText.trim().replace(/\s+/g, " ");
    if (!text || text.length > 120 || safePattern.test(text)) continue;

    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const category = typeof rawCategory === "string" &&
        PROMPT_CATEGORY_ALLOWLIST.has(rawCategory)
      ? rawCategory
      : "generic";

    suggestions.push({ text, category });
    if (suggestions.length === 3) break;
  }

  return suggestions;
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
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;

    const action = normalizeAction(parsedBody.action);
    const scanId = requireUuid(parsedBody.scan_id, "scan_id");
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
      return jsonResponse({ data: responsePayload(null, [], sendsToday) }, 200);
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
          data: {
            conversation_id: existingConversation?.id ?? null,
            prompts: suggestions.prompts,
          },
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
        return jsonResponse({
          code: "prompt_suggestions_unavailable",
          error: "Prompt suggestions are unavailable right now.",
        }, 502);
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
        data: { ok: true, message_id: message.id, rating },
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
        data: { ok: true, id: saved.id, sentiment: saved.sentiment },
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
      return jsonResponse({ data: { summary_text: summary.summaryText } }, 200);
    }

    if (sendsToday >= DAILY_SEND_LIMIT) {
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
          existingConversation?.id ?? null,
          existingConversation
            ? await fetchMessages(existingConversation.id, supabaseAdmin)
            : [],
          sendsToday,
        ),
      }, 429);
    }

    const messageText = normalizeUserMessage(parsedBody.message_text);
    const clientMessageId = parsedBody.client_message_id == null
      ? null
      : requireUuid(parsedBody.client_message_id, "client_message_id");

    const resolvedConversation = await getOrCreateConversation(
      user.id,
      scanId,
      supabaseAdmin,
    );
    const beforeMessages = await fetchMessages(
      resolvedConversation.id,
      supabaseAdmin,
    );
    if (
      clientMessageId &&
      beforeMessages.some((message) =>
        message.client_message_id === clientMessageId
      )
    ) {
      return jsonResponse({
        data: responsePayload(
          resolvedConversation.id,
          beforeMessages,
          sendsToday,
        ),
      }, 200);
    }
    assertConversationHasRoom(beforeMessages.length);

    const startedAt = Date.now();
    let assistantResult: ModelChatResult;
    const localRefusalReason = isSafetyCriticalQuestion(messageText);
    const quotaLease = localRefusalReason
      ? null
      : await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "insight_chat_reply",
        requestId: clientMessageId ?? parsedBody.ai_request_id,
      });
    let userMessage: Awaited<ReturnType<typeof insertUserMessage>>;
    try {
      userMessage = await insertUserMessage(
        resolvedConversation.id,
        user.id,
        scanId,
        messageText,
        clientMessageId,
        supabaseAdmin,
      );
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
        const userPrompt = buildUserPrompt(beforeMessages, messageText);
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

    await insertAssistantMessage(
      resolvedConversation.id,
      user.id,
      scanId,
      assistantResult,
      supabaseAdmin,
      quotaLease?.reservation.model,
    );

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
        resolvedConversation.id,
        messages,
        sendsToday + 1,
      ),
    }, 200);
  })
);
