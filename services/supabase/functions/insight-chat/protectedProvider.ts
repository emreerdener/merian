import {
  decodeGeminiApplication,
  enterGeminiTransport,
} from "../_shared/ai/geminiTransport.ts";
import type { GeminiTransportHooks } from "../_shared/ai/geminiTransport.ts";
import {
  buildFieldChatReplyRequest,
  parseFieldChatReply,
} from "../_shared/fieldChat/reply.ts";
import {
  fetchWithDeadline,
  readResponseJsonWithinLimit,
} from "../_shared/outbound.ts";
import { parseProtectedChatReply } from "./protectedReply.ts";
import {
  geminiResponseReceipt,
  GeminiResponseRejected,
  normalizeGeminiEnvelope,
} from "../_shared/ai/geminiEnvelope.ts";
import { GEMINI_SUPPORT_MODEL } from "../_shared/ai/geminiProfiles.ts";

export const PROTECTED_CHAT_PROVIDER_MS = 90_000;
const MODEL = "gemini-2.5-flash";
function unknown(): never {
  throw new Error("field_chat_execution_held");
}
/** Normalize metadata before enforcing the application's closed JSON contract. */
export function decodeProtectedChatProvider(value: unknown, model = MODEL) {
  const envelope = normalizeGeminiEnvelope(value, model, 32 * 1024);
  const receipt = geminiResponseReceipt(envelope);
  try {
    if (envelope.failure || !envelope.text) throw new Error();
    const answer = parseFieldChatReply(envelope.text);
    const u = envelope.usage;
    return parseProtectedChatReply({
      answer: answer.answer,
      model,
      is_refusal: answer.is_refusal,
      refusal_reason: answer.refusal_reason,
      usage: u
        ? {
          prompt_tokens: u.promptTokens,
          candidate_tokens: u.candidateTokens,
          thinking_tokens: u.thinkingTokens,
          total_tokens: u.totalTokens,
          cached_tokens: u.cachedTokens,
          modality_breakdown: u.modalityBreakdown,
        }
        : null,
    });
  } catch {
    throw new GeminiResponseRejected(receipt);
  }
}
/** Prepare before the irreversible grant; only its execution owner invokes once afterward. */
export function prepareProtectedChatProvider(
  systemInstruction: string,
  userPrompt: string,
  model: string,
  dependencies: {
    apiKey?: () => string | undefined;
    fetcher?: typeof fetch;
    transport?: GeminiTransportHooks;
  } = {},
) {
  if (model !== MODEL && model !== GEMINI_SUPPORT_MODEL) return unknown();
  const apiKey =
    (dependencies.apiKey ?? (() => Deno.env.get("GEMINI_PAID_API_KEY")))()
      ?.trim();
  if (!apiKey) return unknown();
  const request = buildFieldChatReplyRequest(
    systemInstruction,
    userPrompt,
    model,
  );
  const config = request.config!;
  const body = JSON.stringify({
    systemInstruction: { role: "user", parts: [{ text: systemInstruction }] },
    contents: request.contents,
    generationConfig: {
      temperature: config.temperature,
      maxOutputTokens: config.maxOutputTokens,
      responseMimeType: config.responseMimeType,
      responseSchema: config.responseSchema,
      thinkingConfig: config.thinkingConfig,
      ...(model === MODEL ? { candidateCount: 1 } : {}),
    },
  });
  if (new TextEncoder().encode(body).byteLength > 192 * 1024) return unknown();
  let invoked = false;
  return async (signal: AbortSignal) => {
    if (invoked) return unknown();
    invoked = true;
    const deadline = AbortSignal.any([
      signal,
      AbortSignal.timeout(PROTECTED_CHAT_PROVIDER_MS),
    ]);
    try {
      deadline.throwIfAborted();
      await enterGeminiTransport(dependencies.transport, model);
      const response = await fetchWithDeadline(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          redirect: "error",
          signal: deadline,
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body,
        },
        {
          fetcher: dependencies.fetcher,
          timeoutMs: PROTECTED_CHAT_PROVIDER_MS,
        },
      );
      if (
        !response.ok ||
        response.headers.get("content-type")?.split(";")[0].trim()
            .toLowerCase() !== "application/json"
      ) {
        void response.body?.cancel().catch(() => {});
        return unknown();
      }
      const bounded = response.body
        ? new Response(
          response.body.pipeThrough(
            new TransformStream<Uint8Array, Uint8Array>(),
            { signal: deadline },
          ),
          { headers: response.headers, status: response.status },
        )
        : response;
      const result = await readResponseJsonWithinLimit(bounded, 32 * 1024);
      deadline.throwIfAborted();
      await dependencies.transport?.recordResponse(
        geminiResponseReceipt(normalizeGeminiEnvelope(result, model)),
      );
      return await decodeGeminiApplication(
        dependencies.transport,
        () => decodeProtectedChatProvider(result, model),
        (reply) => reply.is_refusal ? "refusal" : "success",
      );
    } catch (error) {
      if (error instanceof GeminiResponseRejected) throw error;
      return unknown();
    }
  };
}
