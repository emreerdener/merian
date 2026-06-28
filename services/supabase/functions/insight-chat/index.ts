import { Type } from "npm:@google/genai@1.0.0";
import { requireUuid } from "../_shared/explore.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { resolveTierForUser } from "../_shared/tierCache.ts";
import {
  countUserSendsToday,
  deleteConversation,
  fetchConversation,
  fetchOwnedAssistantMessage,
  fetchMessages,
  fetchOwnedScan,
  formatMessage,
  getOrCreateConversation,
  insertAssistantMessage,
  insertUserMessage,
  upsertMessageFeedback,
} from "./db.ts";
import {
  assertConversationHasRoom,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeFeedbackNote,
  normalizeFeedbackRating,
  normalizeUserMessage,
  refusalAnswer,
} from "./guards.ts";
import { buildSystemInstruction, buildUserPrompt } from "./prompt.ts";
import {
  DAILY_SEND_LIMIT,
  INSIGHT_CHAT_MODEL,
  InsightChatMessageRow,
  InsightChatResponsePayload,
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
  ModelChatResult,
} from "./types.ts";

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
    model: INSIGHT_CHAT_MODEL,
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
Use only observation-relevant details. Do not replace existing notes. Do not add
medical, edible, legal, pesticide, or exact-location instructions.`;

  const result = await _genAI.models.generateContent({
    model: INSIGHT_CHAT_MODEL,
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
  const summaryText = typeof parsed.summary_text === "string" &&
      parsed.summary_text.trim()
    ? parsed.summary_text.trim()
    : "Field chat discussed the saved observation and follow-up identification context.";
  return { summaryText, usage: result.usageMetadata };
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
        error: "Insight chat requires Merian Pro.",
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

    if (action === "summarize_notes") {
      if (!existingConversation) {
        return jsonResponse({
          code: "conversation_not_found",
          error: "No chat messages to summarize.",
        }, 404);
      }
      const messages = await fetchMessages(existingConversation.id, supabaseAdmin);
      if (messages.length === 0) {
        return jsonResponse({
          code: "conversation_empty",
          error: "No chat messages to summarize.",
        }, 400);
      }
      const startedAt = Date.now();
      const summary = await generateFieldNotesSummary(
        buildSystemInstruction(scan),
        messages,
      );
      const usage = summary.usage;
      trackPostHogEvent(user, "InsightChatNotesSummarized", {
        scan_id: scanId,
        conversation_id: existingConversation.id,
        message_count: messages.length,
        latency_ms: Date.now() - startedAt,
        llm_model: INSIGHT_CHAT_MODEL,
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
    const userMessage = await insertUserMessage(
      resolvedConversation.id,
      user.id,
      scanId,
      messageText,
      clientMessageId,
      supabaseAdmin,
    );

    let assistantResult: ModelChatResult;
    const localRefusalReason = isSafetyCriticalQuestion(messageText);
    if (localRefusalReason) {
      assistantResult = {
        answer: refusalAnswer(localRefusalReason),
        isRefusal: true,
        refusalReason: localRefusalReason,
        usage: null,
      };
    } else {
      try {
        assistantResult = await generateAssistantReply(
          buildSystemInstruction(scan),
          buildUserPrompt(beforeMessages, messageText),
        );
      } catch (error) {
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
      llm_model: assistantResult.usage ? INSIGHT_CHAT_MODEL : null,
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
