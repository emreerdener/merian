/** Pure development candidate. No credential access, transport or admission. */
import type { AIRequest } from "../../functions/_shared/ai/contracts.ts";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import {
  decodeSolPhotoPrimaryDraft,
  type SolPrimaryDraft,
} from "../../functions/_shared/ai/openaiSolPrimaryContract.ts";
import type { OpenAISchema } from "../../functions/_shared/ai/openaiRequest.ts";
import {
  array,
  fields,
  member,
  requireCondition as check,
  text,
} from "./validation.ts";

export const FEATURE_KINDS = [
  "anatomy",
  "shape",
  "colour_pattern",
  "surface_texture",
  "view_coverage",
] as const;
export const FEATURE_VISIBILITY = [
  "visible",
  "not_visible",
  "unclear",
] as const;
export interface PhotoFeature {
  kind: typeof FEATURE_KINDS[number];
  observation: string;
  visibility: typeof FEATURE_VISIBILITY[number];
}
export const FEATURE_PROFILE = "openai_photo_feature_observation_low_v1";
const schema: OpenAISchema = {
  type: "array",
  minItems: 0,
  maxItems: 3,
  description:
    "One to three diagnostic feature observations for biological subjects; zero to three for non-biological subjects. Observations are predictions to be independently reviewed, not evidence of correctness.",
  items: {
    type: "object",
    additionalProperties: false,
    required: ["kind", "observation", "visibility"],
    properties: {
      kind: { type: "string", enum: [...FEATURE_KINDS] },
      observation: { type: "string", minLength: 1, maxLength: 160 },
      visibility: { type: "string", enum: [...FEATURE_VISIBILITY] },
    },
  },
};
const instruction = `

# Diagnostic Feature Observations
Add diagnostic_features: at most three short observations of anatomy, shape, colour/pattern, surface texture or view coverage. Include at least one for a biological subject.
For each observation report visible when the asserted feature is discernible, not_visible when its region is outside the view or fully occluded, or unclear when the region is shown but the feature cannot be resolved. Missing visibility is not biological absence.
Describe only image-grounded features or a specifically unshown/unclear structure. Do not include taxon names, geographic guesses, source captions, confidence scores, odour, microscopic findings, instructions to a reviewer or a reasoning transcript in these observations.
Choose the most specific supported resolution using visible distinguishing features; an unavailable distinguishing feature cannot justify a narrower name. A sharp image may still show only shared characters. Preserve a supported species answer.
Keep the existing explanation format and every other field. Do not claim your feature observations have been verified. This extra field is private evaluation output, never user-facing proof.`;

export function photoFeatureSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoPrimarySnapshot(request),
    profile: FEATURE_PROFILE,
    binding: "openai_photo_feature_observation_evaluation_v1" as const,
    prompt: "openai_identify_vision_feature_observation_v1" as const,
    schema: "merian_openai_feature_observation_evaluation_v1" as const,
  });
}

export function buildPhotoFeatureRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof photoFeatureSnapshot>,
) {
  check(
    JSON.stringify(snapshot) === JSON.stringify(photoFeatureSnapshot(request)),
  );
  const base = buildOpenAIPhotoPrimaryRequest(
    request,
    openAIPhotoPrimarySnapshot(request),
  );
  return {
    ...base,
    instructions: base.instructions + instruction,
    text: {
      ...base.text,
      format: {
        ...base.text.format,
        name: snapshot.schema,
        schema: {
          ...base.text.format.schema,
          required: [
            ...base.text.format.schema.required!,
            "diagnostic_features",
          ],
          properties: {
            ...base.text.format.schema.properties,
            diagnostic_features: structuredClone(schema),
          },
        },
      },
    },
  };
}

/** Transient only: callers must not serialize this result or log parser errors. */
export function decodePhotoFeatureDraft(value: unknown): {
  identification: SolPrimaryDraft;
  features: PhotoFeature[];
} {
  try {
    check(!!value && typeof value === "object" && !Array.isArray(value));
    const { diagnostic_features, ...identification } = value as Record<
      string,
      unknown
    >;
    const primary = decodeSolPhotoPrimaryDraft(identification);
    const features = array(
      diagnostic_features,
      primary.is_biological_subject ? 1 : 0,
      3,
    ).map((raw) => {
      const f = fields(raw, ["kind", "observation", "visibility"]);
      member(f.kind, FEATURE_KINDS);
      member(f.visibility, FEATURE_VISIBILITY);
      text(f.observation, 160);
      check((f.observation as string).trim().length > 0);
      check(
        [...(f.observation as string)].every((c) =>
          c.charCodeAt(0) >= 32 && c.charCodeAt(0) !== 127
        ),
      );
      return {
        kind: f.kind,
        observation: f.observation,
        visibility: f.visibility,
      } as PhotoFeature;
    });
    check(
      new Set(features.map((f) => f.observation.trim().toLowerCase())).size ===
        features.length,
    );
    return { identification: primary, features };
  } catch {
    // Malformed provider text must never escape through exception messages.
    throw new Error("photo_feature_draft_invalid");
  }
}
