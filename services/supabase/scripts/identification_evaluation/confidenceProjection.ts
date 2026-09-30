import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import { OPENAI_MODEL } from "../../functions/_shared/ai/openaiRequest.ts";
import { estimateCost } from "./profiles.ts";
import { projectUsage } from "./projection.ts";
import type { OpenAIPricing } from "./runContracts.ts";
import {
  noIdentityMapping,
  resolveTaxon,
  type ReviewedTaxonomy,
} from "./taxonomy.ts";
import {
  type ConfidenceObservation,
  parseConfidenceObservation,
} from "./confidenceScoring.ts";

export const nanoUsd = (usd: number) => Math.ceil(usd * 1e9);

/** Only taxonomy IDs, rank, numeric evidence and outcomes survive this boundary. */
export function projectConfidenceOutcome(
  caseId: string,
  outcome: AIProviderOutcome,
  taxonomy: ReviewedTaxonomy,
  pricing: OpenAIPricing,
) {
  const usage = projectUsage(outcome.usage, true);
  // Unknown execution and contradictory accounting never release a reservation.
  const usable = outcome.kind !== "unknown_execution" &&
    outcome.kind !== "operational_failure" &&
    outcome.returnedModel === OPENAI_MODEL &&
    outcome.serviceTier === "default" &&
    usage !== null && usage.promptTokens !== null &&
    usage.candidateTokens !== null &&
    usage.thinkingTokens !== null && usage.totalTokens ===
      usage.promptTokens + usage.candidateTokens + usage.thinkingTokens &&
    usage.cachedTokens !== null && usage.toolTokens === 0 &&
    usage.cacheWriteTokens === 0;
  const cost = usable ? estimateCost(pricing, OPENAI_MODEL, usage) : null;
  let observation: ConfidenceObservation = {
    prediction: {
      caseId,
      outcome: outcome.kind === "draft" ? "invalid_output" : outcome.kind,
    },
    mapping: null,
  };
  if (
    outcome.kind === "draft" && outcome.returnedModel === OPENAI_MODEL &&
    outcome.serviceTier === "default"
  ) {
    try {
      const normalized = normalizeIdentification(outcome.draft, {
        hasVisualEvidence: true,
        hasAudioEvidence: false,
        hasInvasiveLocationContext: false,
        confidencePolicy: { kind: "unqualified" },
      });
      const value = normalized.identification;
      const subject = value.is_biological_subject
        ? value.scientific_name?.toLowerCase() === "homo sapiens"
          ? "human"
          : "biological"
        : "non_biological";
      const named = subject === "biological" && !!value.scientific_name;
      const identity = named
        ? resolveTaxon(taxonomy, value.scientific_name!)
        : { taxon: null, mapping: noIdentityMapping() };
      // No invented zero, rank parsing, secondary model or reference lookup.
      observation = parseConfidenceObservation({
        prediction: {
          caseId,
          outcome: "normalized",
          subject,
          resolution: named ? "named" : "unresolved",
          taxon: identity.taxon,
          confidence: value.confidence_score,
        },
        mapping: identity.mapping,
      });
    } catch {
      /* The invalid_output outcome above retains the scheduled case. */
    }
  }
  return { observation, settledNanoUsd: cost === null ? null : nanoUsd(cost) };
}
