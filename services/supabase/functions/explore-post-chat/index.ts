import { Type } from "@google/genai";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireUuid } from "../_shared/explore.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { resolveTierForUser } from "../_shared/entitlement.ts";
import { reserveAIProviderCall } from "../_shared/aiQuota.ts";
import {
  assertConversationHasRoom,
  isSafetyCriticalQuestion,
  normalizeAction,
  normalizeFeedbackNote,
  normalizeFeedbackRating,
  normalizeUserMessage,
  refusalAnswer,
} from "../insight-chat/guards.ts";
import {
  DAILY_SEND_LIMIT,
  INSIGHT_CHAT_MODEL,
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
} from "../insight-chat/types.ts";
import {
  countAllFieldChatSendsToday,
  deleteConversation,
  fetchAssistantMessage,
  fetchConversation,
  fetchMessages,
  fetchPublicContext,
  formatMessage,
  getOrCreateConversation,
  insertAssistantMessage,
  insertUserMessage,
  upsertFeedback,
} from "./db.ts";
import { isExplorePostChatContextAvailable } from "./eligibility.ts";
import { buildSystemInstruction, buildUserPrompt } from "./prompt.ts";
import type {
  ExplorePostChatContext,
  ExplorePostChatMessageRow,
  ModelChatResult,
} from "./types.ts";

const ALLOWED_ACTIONS = new Set([
  "load",
  "send",
  "delete",
  "feedback",
  "suggest_prompts",
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
  messages: ExplorePostChatMessageRow[],
  sendsToday: number,
) {
  return {
    conversation_id: conversationId,
    messages: messages.map(formatMessage),
    limits: limitsPayload(sendsToday),
  };
}

function promptSuggestions(context: ExplorePostChatContext) {
  const commonName = context.post.species_common_name.trim() || "this species";
  const hasLookalikes = (context.detail.similar_species?.length ?? 0) > 0;
  return [
    {
      text: hasLookalikes
        ? `How can I distinguish ${commonName} from lookalikes?`
        : `What traits are characteristic of ${commonName}?`,
      category: hasLookalikes ? "lookalike_compare" : "evidence",
    },
    { text: `What habitat does ${commonName} prefer?`, category: "habitat" },
    {
      text: `What is most interesting about ${commonName}?`,
      category: "ecology",
    },
  ];
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
    answer: typeof parsed.answer === "string" && parsed.answer.trim()
      ? parsed.answer.trim()
      : "I could not produce a useful answer from the public observation context.",
    isRefusal: parsed.is_refusal === true,
    refusalReason: typeof parsed.refusal_reason === "string"
      ? parsed.refusal_reason
      : null,
    usage: result.usageMetadata,
  };
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req);
    if (body instanceof Response) return body;

    const action = normalizeAction(body.action);
    if (!ALLOWED_ACTIONS.has(action)) {
      return jsonResponse({
        code: "unsupported_action",
        error: "Unsupported Explore Field chat action.",
      }, 400);
    }
    const postId = requireUuid(body.post_id, "post_id");
    const context = await fetchPublicContext(user.id, postId, supabaseAdmin);
    if (!isExplorePostChatContextAvailable(context)) {
      return jsonResponse({
        code: "post_not_available",
        error: "This Explore post is not available for Field chat.",
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
    const speciesId = context.detail.species_dictionary_id ?? null;
    let conversation = await fetchConversation(user.id, postId, supabaseAdmin);
    if (conversation?.species_dictionary_id !== speciesId) {
      if (conversation) {
        await deleteConversation(user.id, postId, supabaseAdmin);
      }
      conversation = null;
    }

    if (action === "delete") {
      await deleteConversation(user.id, postId, supabaseAdmin);
      return jsonResponse({ data: responsePayload(null, [], sendsToday) }, 200);
    }

    if (action === "load") {
      const messages = conversation
        ? await fetchMessages(conversation.id, supabaseAdmin)
        : [];
      return jsonResponse({
        data: responsePayload(conversation?.id ?? null, messages, sendsToday),
      }, 200);
    }

    if (action === "suggest_prompts") {
      return jsonResponse({
        data: {
          conversation_id: conversation?.id ?? null,
          prompts: promptSuggestions(context),
        },
      }, 200);
    }

    if (action === "feedback") {
      const messageId = requireUuid(body.message_id, "message_id");
      const rating = normalizeFeedbackRating(body.feedback_rating);
      const note = normalizeFeedbackNote(body.feedback_note);
      const message = await fetchAssistantMessage(
        user.id,
        postId,
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
      trackPostHogEvent(user, "ExplorePostChatFeedbackSubmitted", {
        post_id: postId,
        conversation_id: message.conversation_id,
        message_id: message.id,
        rating,
      }).catch((error) =>
        console.error("Explore post chat feedback telemetry failed:", error)
      );
      return jsonResponse({
        data: { ok: true, message_id: message.id, rating },
      }, 200);
    }

    if (sendsToday >= DAILY_SEND_LIMIT) {
      return jsonResponse({
        code: "daily_limit_reached",
        error: "Daily Field chat limit reached.",
        data: responsePayload(
          conversation?.id ?? null,
          conversation
            ? await fetchMessages(conversation.id, supabaseAdmin)
            : [],
          sendsToday,
        ),
      }, 429);
    }

    const messageText = normalizeUserMessage(body.message_text);
    const clientMessageId = body.client_message_id == null
      ? null
      : requireUuid(body.client_message_id, "client_message_id");
    const resolvedConversation = await getOrCreateConversation(
      user.id,
      postId,
      speciesId,
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
    const refusalReason = isSafetyCriticalQuestion(messageText);
    const quotaLease = refusalReason
      ? null
      : await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "explore_post_chat_reply",
        requestId: clientMessageId ?? body.ai_request_id,
      });
    let userMessage: Awaited<ReturnType<typeof insertUserMessage>>;
    try {
      userMessage = await insertUserMessage(
        resolvedConversation.id,
        user.id,
        postId,
        messageText,
        clientMessageId,
        supabaseAdmin,
      );
    } catch (error) {
      await quotaLease?.refund();
      throw error;
    }

    let assistant: ModelChatResult;
    if (refusalReason) {
      assistant = {
        answer: refusalAnswer(refusalReason).replaceAll(
          "saved scan",
          "public observation",
        ),
        isRefusal: true,
        refusalReason,
        usage: null,
      };
    } else {
      let providerAttempted = false;
      try {
        const systemInstruction = buildSystemInstruction(context);
        const userPrompt = buildUserPrompt(beforeMessages, messageText);
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
          operation: "explore_post_chat_reply",
          model: quotaLease!.reservation.model,
          effectivePlan: tier.plan,
          inputModality: "text",
          outcome: "error",
          userId: user.id,
          conversationId: resolvedConversation.id,
          sourceType: "explore_post",
          sourceId: postId,
        });
        throw error;
      }
    }

    await insertAssistantMessage(
      resolvedConversation.id,
      user.id,
      postId,
      assistant,
      supabaseAdmin,
      quotaLease?.reservation.model,
    );
    const messages = await fetchMessages(
      resolvedConversation.id,
      supabaseAdmin,
    );
    recordAIUsageBestEffort(supabaseAdmin, {
      operation: "explore_post_chat_reply",
      model: quotaLease?.reservation.model ?? INSIGHT_CHAT_MODEL,
      usage: assistant.usage,
      effectivePlan: tier.plan,
      inputModality: "text",
      outcome: assistant.isRefusal ? "refusal" : "success",
      userId: user.id,
      conversationId: resolvedConversation.id,
      messageId: userMessage.id,
      sourceType: "explore_post",
      sourceId: postId,
    });
    trackPostHogEvent(user, "ExplorePostChatSent", {
      post_id: postId,
      conversation_id: resolvedConversation.id,
      message_length: messageText.length,
      is_refusal: assistant.isRefusal,
      latency_ms: Date.now() - startedAt,
      plan: tier.plan,
    }).catch((error) =>
      console.error("Explore post chat telemetry failed:", error)
    );

    return jsonResponse({
      data: responsePayload(resolvedConversation.id, messages, sendsToday + 1),
    }, 200);
  })
);
