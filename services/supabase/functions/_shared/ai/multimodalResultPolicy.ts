import type { AIAttemptSnapshot, AIExecutionOutcome } from "./contracts.ts";
import type { IdentificationConfidencePolicy } from "../identify/normalizeIdentification.ts";
import { assertOpenAIPhotoSnapshot } from "./openaiPhoto.ts";
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
    mediaSafety?: AIExecutionOutcome["mediaSafety"];
  };
}

function resultPolicyKey(snapshot: AIAttemptSnapshot): string {
  if (snapshot.provider === "openai") {
    // Invocation adds timing; it is not part of immutable configuration.
    const { durationMs: _duration, ...configuration } = snapshot as
      & typeof snapshot
      & { durationMs?: number };
    try {
      assertOpenAIPhotoSnapshot(configuration);
    } catch {
      throw new Error("ai_identification_result_policy_unavailable");
    }
    return JSON.stringify(configuration);
  }
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
 * OpenAI scores remain unqualified and provide no Gemini ratings. The exact
 * photo binding has native safety semantics; composition still blocks dispatch.
 */
export function prepareMultimodalResultPolicy(
  snapshot: AIAttemptSnapshot,
): MultimodalResultPolicy {
  const key = resultPolicyKey(snapshot);
  const confidence: IdentificationConfidencePolicy = Object.freeze(
    snapshot.provider === "openai" ? { kind: "unqualified" as const } : {
      kind: "diagnostic_threshold" as const,
      threshold: snapshot.diagnosticTrigger!,
    },
  );
  return Object.freeze({
    confidence,
    safetySignals(result: AIExecutionOutcome) {
      if (resultPolicyKey(result.execution) !== key) {
        throw new Error("ai_identification_result_policy_mismatch");
      }
      if (snapshot.provider === "openai") {
        const safety = result.mediaSafety;
        if (
          result.kind === "draft" &&
          (safety?.provider !== "openai" || safety.policy !== snapshot.safety ||
            safety.disposition !== "allowed" || !result.returnedModel ||
            !/^gpt-6-sol(?:-[a-zA-Z0-9.-]{1,80})?$/.test(result.returnedModel))
        ) {
          throw new Error("ai_identification_safety_unavailable");
        }
        return {
          finishReason: result.finishReason ?? undefined,
          safetyRatings: undefined,
          mediaSafety: safety,
        };
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
