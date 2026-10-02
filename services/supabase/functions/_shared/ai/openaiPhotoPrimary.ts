/** Offline candidate for the current confidence baseline; no dispatch authority. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  type OpenAISchema,
  openAISchemaFromContract,
} from "./openaiRequest.ts";
import { solPhotoPrimaryModelContract } from "./openaiSolPrimaryContract.ts";
import { solPhotoPrimaryInstructions } from "./openaiSolPrimaryInstructions.ts";

export const PHOTO_PRIMARY_PROFILE =
  "openai_photo_confidence_primary_low_v1" as const;
export const PHOTO_PRIMARY_SCHEMA =
  "merian_openai_confidence_primary_evaluation_v1" as const;

export function openAIPhotoPrimarySnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoSnapshot(request, 1),
    binding: "openai_photo_confidence_primary_evaluation_v1" as const,
    contextKind: "evaluation" as const,
    profile: PHOTO_PRIMARY_PROFILE,
    prompt: "openai_identify_vision_confidence_primary_v1" as const,
    schema: PHOTO_PRIMARY_SCHEMA,
  });
}

export function buildOpenAIPhotoPrimaryRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof openAIPhotoPrimarySnapshot>,
) {
  if (
    JSON.stringify(snapshot) !==
      JSON.stringify(openAIPhotoPrimarySnapshot(request))
  ) throw new Error("openai_binding_mismatch");
  const baseline = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  const primary = openAISchemaFromContract(solPhotoPrimaryModelContract);
  // Only these four fields change. In particular, the old primary contract's
  // confidence/traits descriptions must not replace today's reviewed baseline.
  const schema: OpenAISchema = {
    ...baseline.text.format.schema,
    required: [...baseline.text.format.schema.required!, "resolution"],
    properties: {
      ...baseline.text.format.schema.properties,
      resolution: primary.properties!.resolution,
      scientific_name: primary.properties!.scientific_name,
      common_name: primary.properties!.common_name,
      candidates: primary.properties!.candidates,
    },
  };
  return {
    ...baseline,
    instructions: solPhotoPrimaryInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: { ...baseline.text.format, name: snapshot.schema, schema },
    },
  };
}
