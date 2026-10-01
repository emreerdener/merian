/** Confidence assessment uses the exact activated production photo request. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import { OPENAI_PHOTO_CONFIDENCE_PROMPT } from "./openaiConfidenceRules.ts";
export {
  OPENAI_PHOTO_CONFIDENCE_PROMPT,
  OPENAI_PHOTO_CONFIDENCE_RULE,
  openAIConfidenceInstructions,
  openAIConfidenceSchema,
} from "./openaiConfidenceRules.ts";

/** Separate evaluation authority; never accepted by active production admission. */
export function openAIConfidenceSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoSnapshot(request, 1),
    binding: "openai_photo_confidence_evaluation_v1" as const,
    contextKind: "evaluation" as const,
    prompt: OPENAI_PHOTO_CONFIDENCE_PROMPT,
  });
}

/** Same request bytes as the assessed revision and activated production. */
export function buildOpenAIConfidenceRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof openAIConfidenceSnapshot>,
) {
  if (
    JSON.stringify(snapshot) !==
      JSON.stringify(openAIConfidenceSnapshot(request))
  ) {
    throw new Error("openai_binding_mismatch");
  }
  return buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
}
