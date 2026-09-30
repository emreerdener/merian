import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import { OPENAI_MODEL } from "../../functions/_shared/ai/openaiRequest.ts";
import {
  confidenceAccounting,
  confidenceCost,
} from "./confidenceAccounting.ts";
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

export { nanoUsd } from "./confidenceAccounting.ts";

/** Only taxonomy IDs, rank, numeric evidence and outcomes survive this boundary. */
export function projectConfidenceOutcome(
  caseId: string,
  outcome: AIProviderOutcome,
  taxonomy: ReviewedTaxonomy,
  pricing: OpenAIPricing,
) {
  const accounting = confidenceAccounting(outcome);
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
  return {
    observation,
    accounting,
    settledNanoUsd: confidenceCost(accounting, pricing),
  };
}
