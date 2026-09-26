import { estimateCost, modelPricing } from "./profiles.ts";
import type { EvaluationPricing, StoredUsage } from "./runContracts.ts";

export type CostReason =
  | "complete"
  | "not_measured"
  | "usage_missing"
  | "usage_inconsistent"
  | "cache_write_missing"
  | "modality_usage_missing"
  | "pricing_incompatible"
  | "unattempted"
  | "unknown_execution"
  | "model_mismatch";
export interface RateAwareCost {
  method: "rate_aware_usage_v1";
  status: "complete" | "incomplete" | "not_measured";
  usd: number | null;
  reason: CostReason;
}
const result = (
  reason: CostReason,
  usd: number | null = null,
): RateAwareCost => ({
  method: "rate_aware_usage_v1",
  status: reason === "complete"
    ? "complete"
    : reason === "not_measured"
    ? "not_measured"
    : "incomplete",
  usd,
  reason,
});

/** Current synchronous profiles only: no cache objects, tools or setup/storage operations.
 * Reviewed rates can be tier ceilings; this is a usage-based estimate, not an invoice.
 * The conservative dispatch guard deliberately does not use this function.
 */
export function rateAwareCost(
  pricing: EvaluationPricing | null,
  model: string,
  u: StoredUsage | null,
): RateAwareCost {
  if (!pricing) return result("not_measured");
  if (
    !u ||
    [
      u.promptTokens,
      u.candidateTokens,
      u.thinkingTokens,
      u.totalTokens,
      u.cachedTokens,
      u.toolTokens,
    ].some((n) => n === null || n === undefined)
  ) return result("usage_missing");
  const {
    promptTokens: prompt,
    candidateTokens: candidates,
    thinkingTokens: thinking,
    totalTokens: total,
    cachedTokens: cached,
  } = u;
  if (
    prompt === null || candidates === null || thinking === null ||
    total === null || cached === null
  ) return result("usage_missing");
  if (
    [prompt, candidates, thinking, total, cached, u.toolTokens].some((n) =>
      !Number.isSafeInteger(n) || n! < 0
    ) || u.toolTokens !== 0 || total !== prompt + candidates + thinking ||
    estimateCost(pricing, model, u) === null
  ) return result("usage_inconsistent");
  const p = modelPricing(pricing, model);
  let inputUsd: number;
  if (pricing.version === "evaluation_openai_pricing_v1") {
    const writes = u.cacheWriteTokens;
    if (writes === null || writes === undefined) {
      return result("cache_write_missing");
    }
    if (
      !Number.isSafeInteger(writes) || writes < 0 || cached + writes > prompt
    ) return result("usage_inconsistent");
    // Responses provides a combined input count, not separate text/image counts.
    if (
      p.inputPerMillion.text !== p.inputPerMillion.image ||
      !("cacheWrite" in p.inputPerMillion)
    ) return result("pricing_incompatible");
    inputUsd = (prompt - cached - writes) * p.inputPerMillion.text +
      cached * p.inputPerMillion.cached + writes * p.inputPerMillion.cacheWrite;
  } else {
    if ((u.cacheWriteTokens ?? 0) !== 0 || !("audio" in p.inputPerMillion)) {
      return result("pricing_incompatible");
    }
    const rates = p.inputPerMillion;
    if (u.modalities) {
      const m = u.modalities;
      const sum = (v: { text: number; image: number; audio: number }) =>
        v.text + v.image + v.audio;
      if (
        sum(m.prompt) !== prompt || sum(m.cached) !== cached ||
        sum(m.candidates) !== candidates || sum(m.tool) !== 0 ||
        (["text", "image", "audio"] as const).some((k) =>
          m.cached[k] > m.prompt[k]
        )
      ) return result("usage_inconsistent");
      inputUsd = (["text", "image", "audio"] as const).reduce((n, k) =>
        n + (m.prompt[k] - m.cached[k]) * rates[k], 0) + cached * rates.cached;
    } else {
      if (rates.text !== rates.image || rates.text !== rates.audio) {
        return result("modality_usage_missing");
      }
      inputUsd = (prompt - cached) * rates.text + cached * rates.cached;
    }
  }
  return result(
    "complete",
    (inputUsd + (candidates + thinking) * p.outputPerMillion) / 1e6,
  );
}
