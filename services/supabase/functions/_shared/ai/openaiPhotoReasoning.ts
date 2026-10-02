/** Evaluation-only effort comparison; never admitted by the production catalog. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";

export type PhotoReasoningEffort = "low" | "medium";

export function openAIPhotoReasoningSnapshot(
  request: AIRequest,
  effort: PhotoReasoningEffort,
) {
  if (effort !== "low" && effort !== "medium") {
    throw new Error("openai_reasoning_profile_invalid");
  }
  const production = openAIPhotoSnapshot(request, 1);
  return Object.freeze({
    ...production,
    binding: `openai_photo_sol_${effort}_reasoning_evaluation_v1` as const,
    contextKind: "evaluation" as const,
    generation: Object.freeze({
      ...production.generation,
      reasoningEffort: effort,
    }),
  });
}

export function buildOpenAIPhotoReasoningRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof openAIPhotoReasoningSnapshot>,
) {
  if (
    JSON.stringify(snapshot) !== JSON.stringify(
      openAIPhotoReasoningSnapshot(
        request,
        snapshot.generation.reasoningEffort,
      ),
    )
  ) throw new Error("openai_binding_mismatch");
  const production = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  // Low is byte-for-byte production-equivalent. Medium changes this field only.
  return {
    ...production,
    reasoning: { effort: snapshot.generation.reasoningEffort },
  };
}
