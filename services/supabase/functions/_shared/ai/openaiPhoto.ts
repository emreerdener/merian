/** Dormant photo binding. Admission/production do not select this adapter yet. */
import type { AIRequest, MultimodalAIRequest } from "./contracts.ts";
import {
  assertOpenAIInput,
  buildOpenAIRequestParameters,
  OPENAI_GENERATION,
  OPENAI_MODEL,
  openAIEvaluationSnapshot,
} from "./openaiRequest.ts";

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
  readonly prompt: "openai_identify_vision_v1";
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
    prompt: "openai_identify_vision_v1",
    schema: "merian_openai_identify_v1",
    confidence: "openai_unqualified_v1",
    safety: OPENAI_PHOTO_SAFETY_POLICY,
    moderationModel: OPENAI_PHOTO_MODERATION_MODEL,
    timeoutMs: 90000,
    generation: OPENAI_GENERATION,
  });
}

export function buildOpenAIPhotoRequestParameters(
  request: AIRequest,
  snapshot: OpenAIPhotoSnapshot,
) {
  const expected = openAIPhotoSnapshot(request, snapshot.policyVersion);
  if (JSON.stringify(snapshot) !== JSON.stringify(expected)) {
    throw new Error("openai_binding_mismatch");
  }
  // Preserve the measured baseline prompt and generation settings. Only this
  // distinct binding requests inline moderation; old benchmark profiles do not.
  return {
    ...buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request)),
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
