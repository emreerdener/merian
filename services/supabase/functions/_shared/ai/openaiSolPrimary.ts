/** Offline-only explicit-primary candidate. No registry, runner or credentials. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import { openAISchemaFromContract } from "./openaiRequest.ts";
import { solPhotoPrimaryModelContract } from "./openaiSolPrimaryContract.ts";
import { solPhotoPrimaryInstructions } from "./openaiSolPrimaryInstructions.ts";

export const SOL_PRIMARY_PROFILE = "openai_photo_sol_primary_low_v1" as const;
export const SOL_PRIMARY_PROMPT = "openai_identify_vision_primary_v1" as const;
// Provider-only identity: not the reserved durable PRIMARY_IDENTIFICATION_SCHEMA.
export const SOL_PRIMARY_SCHEMA =
  "merian_openai_primary_evaluation_v1" as const;

export function solPhotoPrimarySnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
    binding: "openai_sol_primary_evaluation_v1" as const,
    profile: SOL_PRIMARY_PROFILE,
    prompt: SOL_PRIMARY_PROMPT,
    schema: SOL_PRIMARY_SCHEMA,
  });
}

export function buildSolPhotoPrimaryRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof solPhotoPrimarySnapshot>,
) {
  if (
    JSON.stringify(snapshot) !==
      JSON.stringify(solPhotoPrimarySnapshot(request))
  ) throw new Error("openai_binding_mismatch");
  const baseline = buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
  return {
    ...baseline,
    instructions: solPhotoPrimaryInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        name: snapshot.schema,
        schema: openAISchemaFromContract(solPhotoPrimaryModelContract),
      },
    },
  };
}
