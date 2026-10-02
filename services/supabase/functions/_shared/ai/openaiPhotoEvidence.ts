/** Evaluation-only rank guidance applied to the current confidence photo prompt. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  solPhotoRankInstructions,
  solPhotoRankSchema,
} from "./openaiSolRank.ts";

export function openAIPhotoEvidenceSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoSnapshot(request, 1),
    binding: "openai_photo_evidence_evaluation_v1" as const,
    contextKind: "evaluation" as const,
    prompt: "openai_identify_vision_evidence_v1" as const,
  });
}

export function buildOpenAIPhotoEvidenceRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof openAIPhotoEvidenceSnapshot>,
) {
  if (
    JSON.stringify(snapshot) !==
      JSON.stringify(openAIPhotoEvidenceSnapshot(request))
  ) {
    throw new Error("openai_binding_mismatch");
  }
  const baseline = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  // Reuse reviewed evidence-limit wording; no benchmark identities or answer hints.
  // Only instructions/descriptions change. Shape, explanation, pixels and settings do not.
  return {
    ...baseline,
    instructions: solPhotoRankInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        schema: solPhotoRankSchema(baseline.text.format.schema),
      },
    },
  };
}
