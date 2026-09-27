import type { AIAttemptSnapshot, AIExecutionOutcome } from "./contracts.ts";
import type { IdentificationConfidencePolicy } from "../identify/normalizeIdentification.ts";
import {
  FLASH_DIAGNOSTIC_TRIGGER,
  PRO_DIAGNOSTIC_TRIGGER,
} from "../identify/thresholds.ts";

export interface MultimodalResultPolicy {
  readonly confidence: IdentificationConfidencePolicy;
  /** Only the qualified provider's native signals may reach media promotion. */
  safetySignals(result: AIExecutionOutcome): {
    finishReason: string | undefined;
    safetyRatings: AIExecutionOutcome["safetyRatings"];
  };
}

function resultPolicyKey(snapshot: AIAttemptSnapshot): string {
  const audio = snapshot.schema === "merian_audio_v2" &&
    snapshot.confidence === "gemini_audio_v2" &&
    ["identify_audio_v2", "identify_audio_uncertainty_experiment_v1"].includes(
      snapshot.prompt,
    );
  const visualOrText = snapshot.schema === "merian_identify_v1" &&
    snapshot.confidence === "gemini_identify_v1" &&
    ["identify_vision_v1", "identify_text_v1", "identify_blended_v1"].includes(
      snapshot.prompt,
    );
  if (
    snapshot.provider !== "gemini" ||
    snapshot.binding !== "gemini_baseline_v1" ||
    snapshot.task !== "identify" || snapshot.variant !== "multimodal" ||
    snapshot.contextKind !== "user_request" ||
    snapshot.operation !== "scan_identification" ||
    snapshot.permission !== "google_gemini" ||
    !["gemini-2.5-flash", "gemini-2.5-pro"].includes(snapshot.model) ||
    (!audio && !visualOrText) ||
    snapshot.safety !== undefined ||
    (snapshot.diagnosticTrigger !== FLASH_DIAGNOSTIC_TRIGGER &&
      snapshot.diagnosticTrigger !== PRO_DIAGNOSTIC_TRIGGER)
  ) {
    throw new Error("ai_identification_result_policy_unavailable");
  }
  return JSON.stringify([
    snapshot.provider,
    snapshot.binding,
    snapshot.model,
    snapshot.prompt,
    snapshot.schema,
    snapshot.confidence,
    snapshot.diagnosticTrigger,
  ]);
}

/**
 * Independent result qualification, checked before quota commitment. Adapter
 * registration alone cannot grant confidence or durable-media safety semantics.
 * OpenAI evaluation scores remain unqualified and provide no Gemini ratings;
 * no production OpenAI result policy is enabled here.
 */
export function prepareMultimodalResultPolicy(
  snapshot: AIAttemptSnapshot,
): MultimodalResultPolicy {
  const key = resultPolicyKey(snapshot);
  const confidence = Object.freeze({
    kind: "diagnostic_threshold" as const,
    threshold: snapshot.diagnosticTrigger!,
  });
  return Object.freeze({
    confidence,
    safetySignals(result: AIExecutionOutcome) {
      if (resultPolicyKey(result.execution) !== key) {
        throw new Error("ai_identification_result_policy_mismatch");
      }
      // Preserve Gemini's existing absent-rating and probability behavior only
      // after proving the provider/profile. Missing OpenAI ratings are not safe.
      return {
        finishReason: result.finishReason ?? undefined,
        safetyRatings: result.safetyRatings,
      };
    },
  });
}
