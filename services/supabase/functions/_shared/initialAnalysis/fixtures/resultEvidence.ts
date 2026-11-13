/** Synthetic shared result fixtures; imported only by deterministic tests. */
import type { AIExecutionOutcome } from "../../ai/contracts.ts";
import { openAIPhotoSnapshot } from "../../ai/openaiPhoto.ts";
import { identificationProvenance } from "../../ai/provenance.ts";
import { captureInitialResult } from "../resultEvidence.ts";
export const id = "00000000-0000-4000-8000-000000000101";
export const other = "00000000-0000-4000-8000-000000000102";
export const binding = {
  owner_id: id,
  scan_id: id,
  submission_digest: "a".repeat(64),
  config_digest: "b".repeat(64),
  funding_binding_id: id,
  funding_binding_digest: "c".repeat(64),
  admission_receipt_id: id,
  admission_receipt_digest: "d".repeat(64),
};
export const snapshot = openAIPhotoSnapshot({
  task: "identify",
  variant: "multimodal",
  evidence: [{
    kind: "image",
    order: 0,
    inputIndex: 0,
    lineage: null,
    data: "AA==",
    mimeType: "image/jpeg",
  }],
  capture: {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  },
}, 1);
export const outcome: Extract<AIExecutionOutcome, { kind: "draft" }> = {
  kind: "draft",
  draft: { unvalidated: "not the stored result" },
  execution: { ...snapshot, durationMs: 10 },
  providerDurationMs: 10,
  providerCompletedAt: 1000,
  returnedModel: "gpt-6-sol",
  usage: null,
  finishReason: "completed",
  responseCharacters: 25,
};
export function data(): Record<string, unknown> {
  return {
    scan_id: id,
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Danaus plexippus",
    common_name: "Monarch Butterfly",
    confidence_score: 0.87,
    ai_reasoning: "Synthetic identification fixture.",
    extracted_visual_traits: ["synthetic wings"],
    candidates: [{
      scientific_name: "Danaus gilippus",
      confidence_score: 0.2,
      distinguishing_feature: "synthetic difference",
    }],
    image_quality: {
      sharpness: 8,
      framing: 7,
      diagnostic_utility: 9,
      overall_score: 82,
    },
    pet_identification: null,
    inference_tier: "flash",
    blur_score: 0.2,
    colors: [],
    estimated_size_cm: 8.5,
    insight_data: {
      ai_reasoning: "Synthetic identification fixture.",
      hazard_type: "none",
    },
    identification_provenance: identificationProvenance(snapshot),
  };
}
export function capture(value: unknown = data()) {
  return captureInitialResult({
    binding,
    invocationId: id,
    resultEvidenceId: other,
    outcome,
    data: value,
  });
}
