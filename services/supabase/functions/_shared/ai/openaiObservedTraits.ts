/** Offline-only visual-evidence candidate; no dispatch or production admission. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import type { OpenAISchema } from "./openaiRequest.ts";

export const OBSERVED_TRAITS_PROFILE =
  "openai_photo_sol_observed_traits_low_v1" as const;
export const OBSERVED_TRAITS_PROMPT =
  "openai_identify_vision_observed_traits_v1" as const;
export const OBSERVED_TRAITS_SCHEMA =
  "merian_openai_observed_traits_v1" as const;

const originalInstruction =
  "You MUST extract 3 structural observations in `extracted_visual_traits` BEFORE determining `is_biological_subject` or `scientific_name`.";
const candidateInstruction =
  "Extract one to three distinct physical or structural observations in `extracted_visual_traits` BEFORE determining `is_biological_subject` or `scientific_name`. Include only features directly supported by the supplied visual evidence. If only one or two features are supportable, return those; never invent, repeat or infer unseen anatomy to reach three. Keep material visibility limitations in the existing 1–3 sentence `ai_reasoning`, not as substitute traits.";
const originalDescription =
  "Extract exactly 3 distinct physical or structural traits observed in the visual evidence (e.g. 'smooth texture', 'embedded in concrete', 'green leaves').";
const candidateDescription =
  "Extract one to three distinct physical or structural traits directly supported by the supplied visual evidence. Return only supportable observations, without inventing, repeating or inferring unseen anatomy to reach three. Visibility limitations belong in ai_reasoning, not as substitute traits.";

export function openAIObservedTraitsInstructions(baseline: string): string {
  if (baseline.split(originalInstruction).length !== 2) {
    throw new Error("openai_observed_traits_baseline_drift");
  }
  return baseline.replace(originalInstruction, candidateInstruction);
}

export function openAIObservedTraitsSchema(
  baseline: OpenAISchema,
): OpenAISchema {
  const traits = baseline.properties?.extracted_visual_traits;
  if (
    !traits || traits.description !== originalDescription ||
    traits.type !== "array" || traits.minItems !== 1 || traits.maxItems !== 10
  ) throw new Error("openai_observed_traits_schema_drift");
  return {
    ...baseline,
    properties: {
      ...baseline.properties,
      extracted_visual_traits: { ...traits, description: candidateDescription },
    },
  };
}

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
