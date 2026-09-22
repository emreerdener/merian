import {
  ApiError,
  type GenerateContentParameters,
  HarmBlockThreshold,
  HarmCategory,
} from "@google/genai";
import { _genAI, extractJson, GEMINI_REQUEST_TIMEOUT_MS } from "../gemini.ts";
import { geminiUsageModalityBreakdown } from "../aiUsage.ts";
import { buildGeminiContent } from "./geminiContent.ts";
import {
  getDescribeResponseSchema,
  getDescribeSystemInstruction,
} from "../../identify-describe/schema.ts";
import {
  BIOACOUSTIC_SYSTEM_INSTRUCTION,
  DESCRIBE_SYSTEM_INSTRUCTION,
  MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION,
} from "../../identify-multimodal/instructions.ts";
import { BIOACOUSTIC_SYSTEM_INSTRUCTION as AUDIO_COMPAT_INSTRUCTION } from "../../audio-spec/instructions.ts";
import {
  getMerianAudioResponseSchema,
  getMerianResponseSchema,
  getSystemInstruction,
} from "../identify/schema.ts";
import type {
  AIAdapter,
  AIAttemptSnapshot,
  AIProviderOutcome,
  AIRequest,
  AIResponseFacts,
} from "./contracts.ts";

// Preserve the legacy vision route's explicit biological-photography policy.
// Primary multimodal and audio/description routes keep SDK safety defaults.
const BIOLOGICAL_SAFETY_SETTINGS = [
  {
    category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
    threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
  },
  {
    category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
    threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
  },
];

function diagnosticTrigger(snapshot: AIAttemptSnapshot): number {
  if (
    typeof snapshot.diagnosticTrigger !== "number" ||
    !Number.isFinite(snapshot.diagnosticTrigger)
  ) {
    throw new Error("ai_diagnostic_binding_missing");
  }
  return snapshot.diagnosticTrigger;
}

export function buildGeminiRequest(
  request: AIRequest,
  snapshot: AIAttemptSnapshot,
): GenerateContentParameters {
  const options = snapshot.generation;
  const content = request.task === "identify"
    ? null
    : buildGeminiContent(request);
  const systemInstruction = content?.systemInstruction ??
    (snapshot.prompt === "identify_describe_v1"
      ? getDescribeSystemInstruction()
      : snapshot.prompt === "identify_blended_v1"
      ? MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION
      : snapshot.prompt === "identify_vision_v1"
      ? getSystemInstruction(
        snapshot.promptDiagnosticTrigger ?? diagnosticTrigger(snapshot),
      )
      : snapshot.prompt === "identify_audio_v1"
      ? BIOACOUSTIC_SYSTEM_INSTRUCTION
      : snapshot.prompt === "identify_audio_compat_v1"
      ? AUDIO_COMPAT_INSTRUCTION
      : DESCRIBE_SYSTEM_INSTRUCTION);
  const schema = content?.responseSchema ??
    (snapshot.schema === "merian_describe_v1"
      ? getDescribeResponseSchema()
      : snapshot.schema === "merian_audio_v1"
      ? getMerianAudioResponseSchema()
      : getMerianResponseSchema(diagnosticTrigger(snapshot)));
  return {
    model: snapshot.model,
    contents: request.task === "identify"
      ? [{
        role: "user",
        parts: request.evidence.map((item) =>
          item.kind === "text"
            ? { text: item.text }
            : { inlineData: { mimeType: item.mimeType, data: item.data } }
        ),
      }]
      : content!.contents,
    config: {
      systemInstruction,
      temperature: options.temperature,
      ...(options.seed === undefined ? {} : { seed: options.seed }),
      ...(options.topK === undefined ? {} : { topK: options.topK }),
      maxOutputTokens: options.maxOutputTokens,
      ...(options.thinkingBudget === undefined
        ? {}
        : { thinkingConfig: { thinkingBudget: options.thinkingBudget } }),
      responseMimeType: "application/json",
      responseSchema: structuredClone(schema),
      ...(snapshot.safety === "biological_vision_v1"
        ? { safetySettings: structuredClone(BIOLOGICAL_SAFETY_SETTINGS) }
        : {}),
    },
  };
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
