/** Reviewed evaluation profiles. No runtime settings, endpoint or production selector. */
import type { MultimodalAIRequest } from "../../functions/_shared/ai/contracts.ts";
import { buildGeminiRequestParameters } from "../../functions/_shared/ai/geminiRequest.ts";
import {
  assertOpenAIInput,
  buildOpenAIRequestParameters,
  isOpenAIProfile,
  OPENAI_CANDIDATE_PROFILES,
  OPENAI_NULL_FIELDS_PROFILE,
  openAIEvaluationSnapshot,
} from "../../functions/_shared/ai/openaiRequest.ts";
import {
  OPENAI_NULL_FIELDS_PROMPT_DIGEST,
  OPENAI_NULL_FIELDS_SCHEMA_DIGEST,
} from "../../functions/_shared/ai/openaiNullFields.ts";
import { resolveAIClaim } from "../../functions/_shared/ai/registry.ts";
import type { EvaluationInput } from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  assignmentFor,
  confidencePolicy,
  fixtureAuthority,
} from "./profiles.ts";
import type { EvaluationPricing } from "./runContracts.ts";
import { member, requireCondition as check } from "./validation.ts";

export const REUSABLE_PROFILE_IDS = [
  "gemini_photo_text_v1",
  "openai_photo_text_v1",
  ...OPENAI_CANDIDATE_PROFILES,
  OPENAI_NULL_FIELDS_PROFILE,
] as const;
export const NULL_FIELDS_PROFILES = [
  "openai_photo_text_v1",
  OPENAI_NULL_FIELDS_PROFILE,
] as const;
export type ReusableProfileId = typeof REUSABLE_PROFILE_IDS[number];

export function executionProfile(id: ReusableProfileId) {
  member(id, REUSABLE_PROFILE_IDS);
  if (
    id === OPENAI_NULL_FIELDS_PROFILE || id === OPENAI_CANDIDATE_PROFILES[0] ||
    id === OPENAI_CANDIDATE_PROFILES[1]
  ) return id;
  return id === "openai_photo_text_v1"
    ? "openai_gpt_6_sol" as const
    : "gemini_pro" as const;
}

/** Fixed invented probes identify the complete request configuration, never evidence.
 * Only hashes of instructions/schema/native settings survive in the descriptor. */
function probe(visual: boolean): MultimodalAIRequest {
  return {
    task: "identify",
    variant: "multimodal",
    capture: {
      hasVideo: false,
      videoClipCount: 0,
      declaredVideoFrameCount: 0,
      videoInferenceFrameCount: 0,
    },
    evidence: visual
      ? [{
        kind: "image",
        order: 0,
        data: "AAAA",
        mimeType: "image/png",
        inputIndex: 0,
        lineage: null,
      }]
      : [{
        kind: "text",
        order: 0,
        source: "observation_context",
        text: "Synthetic configuration probe.",
      }],
  };
}

async function profileBinding(
  request: MultimodalAIRequest,
  legacy: ReturnType<typeof executionProfile>,
  inputGroup: "photos" | "description",
) {
  if (isOpenAIProfile(legacy)) {
    const snapshot = openAIEvaluationSnapshot(request, legacy);
    const { input: _input, ...settings } = buildOpenAIRequestParameters(
      request,
      snapshot,
    );
    const promptDigest = await fingerprintJson(settings.instructions);
    const schemaDigest = await fingerprintJson(settings.text.format.schema);
    if (legacy === OPENAI_NULL_FIELDS_PROFILE) {
      check(
        promptDigest === OPENAI_NULL_FIELDS_PROMPT_DIGEST &&
          schemaDigest === OPENAI_NULL_FIELDS_SCHEMA_DIGEST,
      );
    }
    return {
      inputGroup: inputGroup,
      snapshot,
      policyDigest: await fingerprintJson(snapshot),
      nativeSettingsDigest: await fingerprintJson(settings),
      promptDigest,
      schemaDigest,
    };
  }
  const snapshot = resolveAIClaim(request, fixtureAuthority(legacy, request));
  const { contents: _contents, ...settings } = buildGeminiRequestParameters(
    request,
    snapshot,
  );
  return {
    inputGroup: inputGroup,
    snapshot,
    policyDigest: await fingerprintJson(snapshot),
    nativeSettingsDigest: await fingerprintJson(settings),
    promptDigest: await fingerprintJson(settings.config!.systemInstruction),
    schemaDigest: await fingerprintJson(settings.config!.responseSchema),
  };
}

export async function reusableProfile(id: ReusableProfileId) {
  const legacy = executionProfile(id);
  const bindings = await Promise.all(
    (id === OPENAI_NULL_FIELDS_PROFILE ? [true] : [false, true]).map((visual) =>
      profileBinding(probe(visual), legacy, visual ? "photos" : "description")
    ),
  );
  const definition = {
    version: "identification_profile_v1" as const,
    id,
    role:
      id === OPENAI_NULL_FIELDS_PROFILE || id === OPENAI_CANDIDATE_PROFILES[1]
        ? "candidate" as const
        : id === OPENAI_CANDIDATE_PROFILES[0]
        ? "control" as const
        : "baseline" as const,
    executionProfile: legacy,
    provider: isOpenAIProfile(legacy) ? "openai" as const : "gemini" as const,
    api: isOpenAIProfile(legacy) ? "responses_https_v1" : "generate_content_v1",
    supportedInputs: id === OPENAI_NULL_FIELDS_PROFILE
      ? ["photos"] as const
      : ["photos", "description"] as const,
    cachePolicy:
      id === OPENAI_CANDIDATE_PROFILES[0] || id === OPENAI_CANDIDATE_PROFILES[1]
        ? "explicit_no_breakpoints_v1" as const
        : "automatic_uncontrolled_no_explicit_objects_v1" as const,
    confidenceDigest: await fingerprintJson(confidencePolicy(legacy)),
    bindings,
  };
  return { definition, digest: await fingerprintJson(definition) };
}
export type ReusableProfile = Awaited<ReturnType<typeof reusableProfile>>;

export async function reusableAssignmentFor(
  input: EvaluationInput,
  request: MultimodalAIRequest,
  id: ReusableProfileId,
  attempt: number,
  pricing: EvaluationPricing | null,
) {
  check(input.inputGroup === "photos" || input.inputGroup === "description");
  // Both arms accept the same complete photo/text evidence. Never strip audio/video.
  assertOpenAIInput(request);
  const profile = await reusableProfile(id);
  const assignment = await assignmentFor(
    input,
    request,
    profile.definition.executionProfile,
    attempt,
    pricing,
  );
  const binding = profile.definition.bindings.find((b) =>
    b.inputGroup === input.inputGroup
  );
  check(binding !== undefined);
  const actual = await profileBinding(
    request,
    profile.definition.executionProfile,
    input.inputGroup,
  );
  check(actual.nativeSettingsDigest === binding.nativeSettingsDigest);
  check(
    assignment.policyDigest === binding.policyDigest &&
      assignment.promptDigest === binding.promptDigest &&
      assignment.schemaDigest === binding.schemaDigest &&
      assignment.confidenceDigest === profile.definition.confidenceDigest,
  );
  return assignment;
}
