import { enterGeminiTransport } from "./geminiTransport.ts";
import type { GeminiTransportHooks } from "./geminiTransport.ts";
import { ApiError, type GenerateContentParameters } from "@google/genai";
import { _genAI, extractJson, GEMINI_REQUEST_TIMEOUT_MS } from "../gemini.ts";
import {
  geminiResponseReceipt,
  normalizeGeminiEnvelope,
} from "./geminiEnvelope.ts";
import {
  assertGeminiContentDraft,
  buildGeminiContent,
} from "./geminiContent.ts";
import { buildGeminiRequestParameters } from "./geminiRequest.ts";
import type {
  AIAdapter,
  AIProviderOutcome,
  AIRequest,
  AIResponseFacts,
  GeminiAttemptSnapshot,
} from "./contracts.ts";

/** Preserve the complete request projection while keeping pure identification
 * preparation independent from the SDK's Node environment initialization. */
export function buildGeminiRequest(
  request: AIRequest,
  snapshot: GeminiAttemptSnapshot,
): GenerateContentParameters {
  return buildGeminiRequestParameters(
    request,
    snapshot,
    request.task === "identify" ? undefined : buildGeminiContent(request),
  );
}

export const geminiAdapter: AIAdapter<GeminiAttemptSnapshot> = Object.freeze({
  provider: "gemini",
  prepare(request: AIRequest, snapshot: GeminiAttemptSnapshot) {
    if (snapshot.timeoutMs !== GEMINI_REQUEST_TIMEOUT_MS) {
      throw new Error("ai_timeout_mismatch");
    }
    const parameters = buildGeminiRequest(request, snapshot);
    const models = _genAI.models; // Validate local credentials before commitment.
    return async (hooks?: GeminiTransportHooks): Promise<AIProviderOutcome> => {
      await enterGeminiTransport(hooks, snapshot.model);
      let result;
      const providerStart = performance.now();
      try {
        result = await models.generateContent({ ...parameters });
      } catch (error) {
        // 400/429 establish rejection; transport, abort and server failures may
        // have executed. Neither outcome authorizes a second invocation here.
        return {
          providerDurationMs: Math.max(0, performance.now() - providerStart),
          providerCompletedAt: Date.now(),
          kind: error instanceof ApiError &&
              (error.status === 400 || error.status === 429)
            ? "operational_failure"
            : "unknown_execution",
          returnedModel: null,
          usage: null,
          finishReason: null,
          responseCharacters: 0,
        };
      }
      const providerDurationMs = Math.max(0, performance.now() - providerStart);
      const providerCompletedAt = Date.now();
      const normalized = normalizeGeminiEnvelope(
        result,
        snapshot.model,
        256 * 1024,
      );
      await hooks?.recordResponse(geminiResponseReceipt(normalized));
      const finishReason = normalized.finishReason;
      const text = normalized.text ?? "";
      const facts: AIResponseFacts = {
        providerDurationMs,
        providerCompletedAt,
        safetyRatings: normalized.safetyRatings,
        returnedModel: normalized.returnedModel,
        finishReason,
        responseCharacters: text.length,
        usage: normalized.usage,
      };
      if (normalized.failure && request.task !== "identify") {
        await hooks?.recordApplicationOutcome?.("error");
      }
      if (normalized.failure === "identity") {
        return { ...facts, kind: "invalid_output", reason: "identity" };
      }
      if (normalized.failure === "safety") return { ...facts, kind: "refusal" };
      if (normalized.failure) {
        return {
          ...facts,
          kind: "invalid_output",
          reason: normalized.failure === "finish" ? "finish" : "json",
        };
      }
      let draft: unknown;
      try {
        draft = extractJson<unknown>(text);
        if (request.task !== "identify") {
          assertGeminiContentDraft(
            draft,
            buildGeminiContent(request).responseSchema,
            request.task,
          );
        }
      } catch {
        if (request.task !== "identify") {
          await hooks?.recordApplicationOutcome?.("error");
        }
        return { ...facts, kind: "invalid_output", reason: "json" };
      }
      // Keep acknowledgement failure outside decoding; accepted facts cannot
      // be relabelled as a parser failure or trigger another provider call.
      if (request.task !== "identify") {
        await hooks?.recordApplicationOutcome?.("success");
      }
      return { ...facts, kind: "draft", draft };
    };
  },
});
