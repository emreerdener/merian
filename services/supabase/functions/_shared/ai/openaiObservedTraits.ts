/** Offline-only visual-evidence candidate; no dispatch or production admission. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import {
  openAIObservedTraitsInstructions,
  openAIObservedTraitsSchema,
} from "./openaiPhoto.ts";
export {
  openAIObservedTraitsInstructions,
  openAIObservedTraitsSchema,
} from "./openaiPhoto.ts";

export const OBSERVED_TRAITS_PROFILE =
  "openai_photo_sol_observed_traits_low_v1" as const;
export const OBSERVED_TRAITS_PROMPT =
  "openai_identify_vision_observed_traits_v1" as const;
export const OBSERVED_TRAITS_SCHEMA =
  "merian_openai_observed_traits_v1" as const;

export function openAIObservedTraitsSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
    binding: "openai_observed_traits_evaluation_v1" as const,
    profile: OBSERVED_TRAITS_PROFILE,
    prompt: OBSERVED_TRAITS_PROMPT,
    schema: OBSERVED_TRAITS_SCHEMA,
  });
}

export function buildOpenAIObservedTraitsRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof openAIObservedTraitsSnapshot>,
) {
  if (
    JSON.stringify(snapshot) !==
      JSON.stringify(openAIObservedTraitsSnapshot(request))
  ) throw new Error("openai_binding_mismatch");
  const baseline = buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
  return {
    ...baseline,
    instructions: openAIObservedTraitsInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        name: snapshot.schema,
        schema: openAIObservedTraitsSchema(baseline.text.format.schema),
      },
    },
  };
}
