import type { AIUsage } from "./contracts.ts";
import { geminiReturnedModelMatches } from "./geminiProfiles.ts";

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
function count(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value >= 0 && value <= 100_000_000
    ? value
    : null;
}
function modalities(value: unknown): Record<string, number> {
  if (!Array.isArray(value) || value.length > 16) return {};
  const output: Record<string, number> = {};
  for (const item of value) {
    const row = record(item);
    if (
      !row || typeof row.modality !== "string" ||
      !["TEXT", "IMAGE", "VIDEO", "AUDIO", "DOCUMENT"].includes(row.modality) ||
      Object.hasOwn(output, row.modality.toLowerCase()) ||
      count(row.tokenCount) === null
    ) return {};
    output[row.modality.toLowerCase()] = row.tokenCount as number;
  }
  return output;
}

export interface GeminiEnvelope {
  returnedModel: string | null;
  usage: AIUsage | null;
  usageConsistent: boolean;
  finishReason: string | null;
  text: string | null;
  failure: "envelope" | "identity" | "safety" | "finish" | "parts" | null;
  safetyRatings?: readonly { probability?: string }[];
}

/** Extract bounded accounting before inspecting answer semantics. Never retain thoughts. */
export function normalizeGeminiEnvelope(
  value: unknown,
  requestedModel: string,
  maximumBytes = 32 * 1024,
): GeminiEnvelope {
  const empty: GeminiEnvelope = {
    returnedModel: null,
    usage: null,
    usageConsistent: false,
    finishReason: null,
    text: null,
    failure: "envelope",
  };
  try {
    if (
      new TextEncoder().encode(JSON.stringify(value)).byteLength > maximumBytes
    ) return empty;
  } catch {
    return empty;
  }
  const root = record(value);
  if (!root) return empty;
  const returnedModel = typeof root.modelVersion === "string" &&
      /^gemini-[a-zA-Z0-9.-]{1,100}$/.test(root.modelVersion)
    ? root.modelVersion
    : null;
  const raw = record(root.usageMetadata);
  const usage: AIUsage | null = raw
    ? {
      promptTokens: count(raw.promptTokenCount),
      candidateTokens: count(raw.candidatesTokenCount),
      thinkingTokens: count(raw.thoughtsTokenCount),
      cachedTokens: count(raw.cachedContentTokenCount),
      toolTokens: count(raw.toolUsePromptTokenCount),
      totalTokens: count(raw.totalTokenCount),
      modalityBreakdown: {
        prompt: modalities(raw.promptTokensDetails),
        cached: modalities(raw.cacheTokensDetails),
        candidates: modalities(raw.candidatesTokensDetails),
        tool: modalities(raw.toolUsePromptTokensDetails),
      },
    }
    : null;
  // Missing optional counters remain unknown in the receipt. They are zero only
  // for checking the provider's sum when the field was omitted, never when invalid.
  const optional = [
    "thoughtsTokenCount",
    "cachedContentTokenCount",
    "toolUsePromptTokenCount",
  ];
  const usageConsistent = !!raw && !!usage &&
    optional.every((key) =>
      raw[key] === undefined || count(raw[key]) !== null
    ) &&
    usage.promptTokens !== null && usage.candidateTokens !== null &&
    usage.totalTokens !== null &&
    usage.totalTokens ===
      usage.promptTokens + usage.candidateTokens + (usage.thinkingTokens ?? 0) +
        (usage.toolTokens ?? 0) &&
    (usage.cachedTokens ?? 0) <= usage.promptTokens;
  const candidate =
    Array.isArray(root.candidates) && root.candidates.length === 1
      ? record(root.candidates[0])
      : null;
  const finishReason = typeof candidate?.finishReason === "string" &&
      /^[A-Z_]{1,80}$/.test(candidate.finishReason)
    ? candidate.finishReason
    : null;
  const result: GeminiEnvelope = {
    returnedModel,
    usage,
    usageConsistent,
    finishReason,
    text: null,
    failure: null,
  };
  if (!geminiReturnedModelMatches(requestedModel, returnedModel)) {
    return { ...result, failure: "identity" };
  }
  const feedback = record(root.promptFeedback);
  const ratingSets = [feedback?.safetyRatings, candidate?.safetyRatings];
  if (
    feedback?.blockReason !== undefined ||
    ratingSets.some((ratings) =>
      ratings !== undefined &&
      (!Array.isArray(ratings) || ratings.length > 16 ||
        ratings.some((rating) => {
          const row = record(rating);
          return !row || (row.blocked !== undefined && row.blocked !== false);
        }))
    )
  ) return { ...result, failure: "safety" };
  if (Array.isArray(candidate?.safetyRatings)) {
    result.safetyRatings = candidate.safetyRatings.map((rating) => {
      const probability = record(rating)?.probability;
      return typeof probability === "string" &&
          /^[A-Z_]{1,40}$/.test(probability)
        ? { probability }
        : {};
    });
  }
  if (finishReason === "SAFETY" || finishReason === "PROHIBITED_CONTENT") {
    return { ...result, failure: "safety" };
  }
  if (!candidate || finishReason !== "STOP") {
    return { ...result, failure: "finish" };
  }
  const content = record(candidate.content);
  if (
    (content?.role !== undefined && content.role !== "model") || !content ||
    !Array.isArray(content.parts) || content.parts.length < 1 ||
    content.parts.length > 32
  ) return { ...result, failure: "parts" };
  const texts: string[] = [];
  for (const item of content.parts) {
    const part = record(item);
    if (
      !part || Object.keys(part).some((key) =>
        !["text", "thought", "thoughtSignature"].includes(key)
      ) ||
      (part.text !== undefined && typeof part.text !== "string") ||
      (part.thought !== undefined && typeof part.thought !== "boolean") ||
      (part.thoughtSignature !== undefined &&
        (typeof part.thoughtSignature !== "string" ||
          part.thoughtSignature.length > maximumBytes))
    ) {
      return { ...result, failure: "parts" };
    }
    if (part.thought !== true && typeof part.text === "string") {
      texts.push(part.text);
    }
  }
  const text = texts.join("");
  return text.trim() ? { ...result, text } : { ...result, failure: "parts" };
}

/** Content-free evidence can survive application rejection. Never attach the envelope. */
export type GeminiResponseReceipt = Pick<
  GeminiEnvelope,
  "returnedModel" | "usage" | "usageConsistent" | "finishReason" | "failure"
>;
export function geminiResponseReceipt(
  envelope: GeminiEnvelope,
): GeminiResponseReceipt {
  const { returnedModel, usage, usageConsistent, finishReason, failure } =
    envelope;
  return { returnedModel, usage, usageConsistent, finishReason, failure };
}
export class GeminiResponseRejected extends Error {
  constructor(
    readonly receipt: GeminiResponseReceipt,
    code = "gemini_response_rejected",
  ) {
    super(code);
    this.name = "GeminiResponseRejected";
  }
}
