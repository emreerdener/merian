import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { OPENAI_MODEL } from "../../functions/_shared/ai/openaiRequest.ts";
import { estimateCost } from "./profiles.ts";
import { projectUsage } from "./projection.ts";
import type { OpenAIPricing } from "./runContracts.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";

export const nanoUsd = (usd: number) => Math.ceil(usd * 1e9);
const counts = [
  "promptTokens",
  "candidateTokens",
  "thinkingTokens",
  "totalTokens",
  "cachedTokens",
  "cacheWriteTokens",
  "toolTokens",
] as const;
type Counts = Record<typeof counts[number], number | null>;
export interface ConfidenceAccounting {
  version: "openai_confidence_accounting_v1";
  modelMatched: boolean;
  defaultTier: boolean;
  executionKnown: boolean;
  cacheWriteCountValid: boolean;
  usage: Counts | null;
}

/** Bounded numeric evidence only; no model text, credentials or request IDs. */
export function confidenceAccounting(
  outcome: AIProviderOutcome,
): ConfidenceAccounting {
  const usage = projectUsage(outcome.usage, true);
  const writes = outcome.usage?.cacheWriteTokens;
  return {
    version: "openai_confidence_accounting_v1",
    modelMatched: outcome.returnedModel === OPENAI_MODEL,
    defaultTier: outcome.serviceTier === "default",
    executionKnown: outcome.kind !== "unknown_execution" &&
      outcome.kind !== "operational_failure",
    cacheWriteCountValid: writes == null ||
      (Number.isSafeInteger(writes) && writes >= 0 && writes <= 100000000),
    usage: usage === null ? null : Object.fromEntries(
      counts.map((key) => [key, usage[key] ?? null]),
    ) as Counts,
  };
}

export function parseConfidenceAccounting(
  value: unknown,
): ConfidenceAccounting {
  const v = fields(value, [
    "version",
    "modelMatched",
    "defaultTier",
    "executionKnown",
    "cacheWriteCountValid",
    "usage",
  ]);
  check(v.version === "openai_confidence_accounting_v1");
  for (
    const k of [
      "modelMatched",
      "defaultTier",
      "executionKnown",
      "cacheWriteCountValid",
    ]
  ) {
    check(typeof v[k] === "boolean");
  }
  if (v.usage !== null) {
    const u = fields(v.usage, [...counts]);
    for (const k of counts) if (u[k] !== null) integer(u[k], 0, 100000000);
  }
  return structuredClone(v) as unknown as ConfidenceAccounting;
}

export function confidenceCost(
  a: ConfidenceAccounting,
  pricing: OpenAIPricing,
) {
  const u = a.usage;
  if (
    !a.modelMatched || !a.defaultTier || !a.executionKnown ||
    !a.cacheWriteCountValid || u === null || u.promptTokens === null ||
    u.candidateTokens === null || u.thinkingTokens === null ||
    u.totalTokens !== u.promptTokens + u.candidateTokens + u.thinkingTokens ||
    u.cachedTokens === null || u.cachedTokens > u.promptTokens ||
    u.toolTokens !== 0 ||
    (u.cacheWriteTokens !== null &&
      u.cachedTokens + u.cacheWriteTokens > u.promptTokens)
  ) return null;
  // Unknown optional write counts stay unknown. Every input token is charged at
  // the maximum reviewed rate, including writes, so no cache discount is assumed.
  const cost = estimateCost(pricing, OPENAI_MODEL, { ...u, modalities: null });
  return cost === null ? null : nanoUsd(cost);
}
