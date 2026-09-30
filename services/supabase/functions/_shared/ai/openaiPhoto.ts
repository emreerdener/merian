/** Photo-only binding. Production selection belongs to database admission. */
import type { AIRequest, MultimodalAIRequest } from "./contracts.ts";
import {
  assertOpenAIInput,
  buildOpenAIRequestParameters,
  OPENAI_GENERATION,
  OPENAI_MODEL,
  openAIEvaluationSnapshot,
  type OpenAISchema,
} from "./openaiRequest.ts";

export const OPENAI_PHOTO_PROMPT = "openai_identify_vision_observed_traits_v1";

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

export const OPENAI_PHOTO_SAFETY_POLICY = "openai_photo_moderation_v1";
export const OPENAI_PHOTO_MODERATION_MODEL = "omni-moderation-2024-09-26";

export interface OpenAIPhotoSnapshot {
  readonly provider: "openai";
  readonly binding: "openai_photo_v1";
  readonly task: "identify";
  readonly variant: "multimodal";
  readonly model: typeof OPENAI_MODEL;
  readonly contextKind: "user_request";
  readonly operation: "scan_identification";
  readonly policyVersion: number;
  readonly permission: "openai";
  readonly prompt: typeof OPENAI_PHOTO_PROMPT;
  readonly schema: "merian_openai_identify_v1";
  readonly confidence: "openai_unqualified_v1";
  readonly safety: typeof OPENAI_PHOTO_SAFETY_POLICY;
  readonly moderationModel: typeof OPENAI_PHOTO_MODERATION_MODEL;
  readonly timeoutMs: 90000;
  readonly generation: typeof OPENAI_GENERATION;
}

export function assertOpenAIPhotoInput(
  request: AIRequest,
): asserts request is MultimodalAIRequest {
  assertOpenAIInput(request);
  if (!request.evidence.some((item) => item.kind === "image")) {
    throw new Error("openai_photo_input_unsupported");
  }
}

/** Configuration facts only: constructing this value grants no admission. */
export function openAIPhotoSnapshot(
  request: AIRequest,
  policyVersion: number,
): OpenAIPhotoSnapshot {
  assertOpenAIPhotoInput(request);
  return photoConfiguration(policyVersion);
}

function photoConfiguration(policyVersion: number): OpenAIPhotoSnapshot {
  if (
    !Number.isSafeInteger(policyVersion) || policyVersion < 1 ||
    policyVersion > 999_999_999
  ) {
    throw new Error("openai_photo_policy_invalid");
  }
  return Object.freeze({
    provider: "openai",
    binding: "openai_photo_v1",
    task: "identify",
    variant: "multimodal",
    model: OPENAI_MODEL,
    contextKind: "user_request",
    operation: "scan_identification",
    policyVersion,
    permission: "openai",
    prompt: OPENAI_PHOTO_PROMPT,
    schema: "merian_openai_identify_v1",
    confidence: "openai_unqualified_v1",
    safety: OPENAI_PHOTO_SAFETY_POLICY,
    moderationModel: OPENAI_PHOTO_MODERATION_MODEL,
    timeoutMs: 90000,
    generation: OPENAI_GENERATION,
  });
}

/** Exact content-free configuration, independently checked before result use. */
export function assertOpenAIPhotoSnapshot(
  snapshot: OpenAIPhotoSnapshot,
): void {
  const expected = photoConfiguration(snapshot.policyVersion);
  const record = snapshot as unknown as Record<string, unknown>;
  if (
    Object.keys(record).length !== Object.keys(expected).length ||
    Object.entries(expected).some(([key, value]) =>
      key === "generation"
        ? JSON.stringify(record[key]) !== JSON.stringify(value)
        : record[key] !== value
    )
  ) {
    throw new Error("openai_binding_mismatch");
  }
}

export function buildOpenAIPhotoRequestParameters(
  request: AIRequest,
  snapshot: OpenAIPhotoSnapshot,
) {
  assertOpenAIPhotoInput(request);
  assertOpenAIPhotoSnapshot(snapshot);
  // The prompt revision owns both evidence directions. The output shape and
  // schema name stay stable; frozen evaluation profiles build the old base directly.
  const baseline = buildOpenAIRequestParameters(
    request,
    openAIEvaluationSnapshot(request),
  );
  return {
    ...baseline,
    instructions: openAIObservedTraitsInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        schema: openAIObservedTraitsSchema(baseline.text.format.schema),
      },
    },
    moderation: { model: snapshot.moderationModel },
  };
}

export interface OpenAIPhotoSafety {
  readonly provider: "openai";
  readonly policy: typeof OPENAI_PHOTO_SAFETY_POLICY;
  readonly disposition: "allowed" | "rejected" | "unavailable";
}

// The pinned moderation snapshot supports only these six image categories.
// Text-only category scores never stand in for image coverage.
const imageCategories = [
  "self-harm",
  "self-harm/intent",
  "self-harm/instructions",
  "sexual",
  "violence",
  "violence/graphic",
] as const;
const textOnlyCategories = [
  "harassment",
  "harassment/threatening",
  "hate",
  "hate/threatening",
  "illicit",
  "illicit/violent",
  "sexual/minors",
] as const;
const categories = [...imageCategories, ...textOnlyCategories];
const object = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
const exactCategories = (value: Record<string, unknown> | null) =>
  value !== null && Object.keys(value).length === categories.length &&
  categories.every((key) => Object.hasOwn(value, key));

function disposition(
  value: unknown,
  imageInput: boolean,
  textInput: boolean,
): OpenAIPhotoSafety["disposition"] {
  const result = object(value);
  const flags = object(result?.categories),
    scores = object(result?.category_scores);
  const applied = object(result?.category_applied_input_types);
  if (
    result?.type !== "moderation_result" ||
    result.model !== OPENAI_PHOTO_MODERATION_MODEL ||
    typeof result.flagged !== "boolean" || !exactCategories(flags) ||
    !exactCategories(scores) || !exactCategories(applied)
  ) return "unavailable";
  let flagged = false;
  for (const category of categories) {
    const flag = flags![category],
      score = scores![category],
      types = applied![category];
    if (
      typeof flag !== "boolean" || typeof score !== "number" ||
      !Number.isFinite(score) || score < 0 || score > 1 ||
      !Array.isArray(types) || types.length > 2 ||
      new Set(types).size !== types.length ||
      types.some((type) => type !== "image" && type !== "text") ||
      (textInput && !types.includes("text")) ||
      (imageInput && imageCategories.some((key) => key === category) &&
        !types.includes("image")) ||
      ((!imageInput || textOnlyCategories.some((key) => key === category)) &&
        types.includes("image"))
    ) {
      return "unavailable";
    }
    flagged ||= flag;
  }
  if (flagged !== result.flagged) return "unavailable";
  return flagged ? "rejected" : "allowed";
}

/** Only bounded policy facts escape; never retain scores, error text or content. */
export function openAIPhotoSafety(
  value: unknown,
  hasObservationText: boolean,
): OpenAIPhotoSafety {
  const moderation = object(value);
  const input = disposition(moderation?.input, true, hasObservationText);
  const output = disposition(moderation?.output, false, true);
  return Object.freeze({
    provider: "openai",
    policy: OPENAI_PHOTO_SAFETY_POLICY,
    // Incomplete evidence cannot establish a rejection or justify an account strike.
    disposition: input === "unavailable" || output === "unavailable"
      ? "unavailable"
      : input === "rejected" || output === "rejected"
      ? "rejected"
      : "allowed",
  });
}
