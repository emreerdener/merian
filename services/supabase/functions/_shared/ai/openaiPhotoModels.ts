/** Closed evaluation profiles; neither is a production admission binding. */
import type { AIRequest } from "./contracts.ts";
import {
  assertOpenAIPhotoInput,
  buildOpenAIPhotoRequestParameters,
  OPENAI_PHOTO_MODERATION_MODEL,
  OPENAI_PHOTO_SAFETY_POLICY,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import { OPENAI_GENERATION } from "./openaiRequest.ts";

export const OPENAI_PHOTO_MODEL_PROFILES = [
  "openai_photo_luna_low_v1",
  "openai_photo_sol_low_v1",
] as const;
export type OpenAIPhotoModelProfile =
  typeof OPENAI_PHOTO_MODEL_PROFILES[number];
export const OPENAI_PHOTO_MODELS = {
  openai_photo_luna_low_v1: "gpt-6-luna",
  openai_photo_sol_low_v1: "gpt-6-sol",
} as const;
export type OpenAIPhotoModel =
  typeof OPENAI_PHOTO_MODELS[OpenAIPhotoModelProfile];

export function isOpenAIPhotoModelProfile(
  value: unknown,
): value is OpenAIPhotoModelProfile {
  return OPENAI_PHOTO_MODEL_PROFILES.some((profile) => value === profile);
}

export function openAIPhotoModelSnapshot(
  request: AIRequest,
  profile: OpenAIPhotoModelProfile,
) {
  assertOpenAIPhotoInput(request);
  if (!isOpenAIPhotoModelProfile(profile)) {
    throw new Error("openai_photo_model_profile_invalid");
  }
  return Object.freeze({
    provider: "openai" as const,
    binding: "openai_photo_models_evaluation_v1" as const,
    contextKind: "evaluation" as const,
    task: "identify" as const,
    variant: "multimodal" as const,
    profile,
    model: OPENAI_PHOTO_MODELS[profile],
    prompt: "openai_identify_vision_v1" as const,
    schema: "merian_openai_identify_v1" as const,
    confidence: "openai_unqualified_v1" as const,
    safety: OPENAI_PHOTO_SAFETY_POLICY,
    moderationModel: OPENAI_PHOTO_MODERATION_MODEL,
    timeoutMs: 90000 as const,
    generation: OPENAI_GENERATION,
  });
}
export type OpenAIPhotoModelSnapshot = ReturnType<
  typeof openAIPhotoModelSnapshot
>;

/** Reuse the complete production photo request; only the reviewed model differs. */
export function buildOpenAIPhotoModelRequestParameters(
  request: AIRequest,
  snapshot: OpenAIPhotoModelSnapshot,
) {
  const expected = openAIPhotoModelSnapshot(request, snapshot.profile);
  if (JSON.stringify(snapshot) !== JSON.stringify(expected)) {
    throw new Error("openai_binding_mismatch");
  }
  // This pure snapshot supplies configuration, never quota or production authority.
  const baseline = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  return { ...baseline, model: snapshot.model };
}
