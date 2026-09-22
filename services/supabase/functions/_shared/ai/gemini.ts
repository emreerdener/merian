import { ApiError, type GenerateContentParameters } from "@google/genai";
import { _genAI, extractJson, GEMINI_REQUEST_TIMEOUT_MS } from "../gemini.ts";
import { geminiUsageModalityBreakdown } from "../aiUsage.ts";
import { buildGeminiContent } from "./geminiContent.ts";
import { buildGeminiRequestParameters } from "./geminiRequest.ts";
import type {
  AIAdapter,
  AIAttemptSnapshot,
  AIProviderOutcome,
  AIRequest,
  AIResponseFacts,
} from "./contracts.ts";

/** Preserve the complete request projection while keeping pure identification
 * preparation independent from the SDK's Node environment initialization. */
export function buildGeminiRequest(
  request: AIRequest,
  snapshot: AIAttemptSnapshot,
): GenerateContentParameters {
  return buildGeminiRequestParameters(
    request,
    snapshot,
    request.task === "identify" ? undefined : buildGeminiContent(request),
  );
}

export const geminiAdapter: AIAdapter = Object.freeze({
  provider: "gemini",
  prepare(request: AIRequest, snapshot: AIAttemptSnapshot) {
    if (snapshot.timeoutMs !== GEMINI_REQUEST_TIMEOUT_MS) {
      throw new Error("ai_timeout_mismatch");
    }
    const parameters = buildGeminiRequest(request, snapshot);
    const models = _genAI.models; // Validate local credentials before commitment.
    return async (): Promise<AIProviderOutcome> => {
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
      const candidate = result.candidates?.[0];
      const finishReason = candidate?.finishReason ?? null;
      let text = result.text ?? "";
      if (
        !text && request.task === "identify" && request.variant !== "multimodal"
      ) {
        const firstPart = candidate?.content?.parts?.[0];
        if (typeof firstPart?.text === "string") text = firstPart.text;
      }
      const usage = result.usageMetadata;
      const facts: AIResponseFacts = {
        providerDurationMs,
        providerCompletedAt,
        safetyRatings: candidate?.safetyRatings?.map((rating) => ({
          probability: rating.probability,
        })),
        returnedModel: result.modelVersion &&
            /^gemini-[a-zA-Z0-9.-]{1,100}$/.test(result.modelVersion)
          ? result.modelVersion
          : null,
        finishReason,
        responseCharacters: text.length,
        usage: usage
          ? {
            promptTokens: usage.promptTokenCount ?? null,
            candidateTokens: usage.candidatesTokenCount ?? null,
            totalTokens: usage.totalTokenCount ?? null,
            thinkingTokens: usage.thoughtsTokenCount ?? null,
            cachedTokens: usage.cachedContentTokenCount ?? null,
            ...(usage.toolUsePromptTokenCount === undefined
              ? {}
              : { toolTokens: usage.toolUsePromptTokenCount }),
            modalityBreakdown: geminiUsageModalityBreakdown(usage),
          }
          : null,
      };
      // Identification has explicit finish-policy guards. Content helpers
      // historically parse the returned text regardless of finish reason.
      if (
        request.task === "identify" &&
        (finishReason === "SAFETY" || finishReason === "PROHIBITED_CONTENT")
      ) {
        return { ...facts, kind: "refusal" };
      }
      if (
        request.task === "identify" && finishReason &&
        finishReason !== "STOP" &&
        finishReason !== "FINISH_REASON_UNSPECIFIED"
      ) return { ...facts, kind: "invalid_output", reason: "finish" };
      try {
        return { ...facts, kind: "draft", draft: extractJson<unknown>(text) };
      } catch {
        return { ...facts, kind: "invalid_output", reason: "json" };
      }
    };
  },
});
