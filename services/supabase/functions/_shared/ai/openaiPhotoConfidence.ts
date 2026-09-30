/** Prepared photo revision. The production selector remains reader-first gated. */
import type { OpenAISchema } from "./openaiRequest.ts";
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";

export const OPENAI_PHOTO_CONFIDENCE_PROMPT =
  "openai_identify_vision_confidence_v1";
export const OPENAI_PHOTO_CONFIDENCE_RULE =
  "Estimate the likelihood that the displayed primary identification is correct at the taxonomic level actually named, from 0.0 to 1.0. Base the estimate on the available identifying visual evidence and genuinely plausible competing identities. Missing or ambiguous diagnostic evidence should reduce confidence; do not require exclusion of every theoretical lookalike. Uncertainty about a cultivar, subspecies, sex, or another finer detail does not automatically reduce confidence in a supported species identification. Supplying required alternative candidates does not itself lower confidence. There is no prescribed score range for ordinary photographs or target distribution of scores. Geography and season retain their identification tie-breaking role but supply no automatic confidence bonus; neither model nor subscription tier supplies a bonus. This is a model-generated estimate, not an empirically calibrated probability. For an unresolved or non-biological answer, the score concerns that classification decision, not an invented species identity.";

const originalInstruction =
  "- **Confidence Scoring:** `confidence_score` must be derived *solely* from morphological features visible in the visual evidence. Local abundance or seasonal expectation does NOT raise confidence. Most field photographs warrant a score of 0.70–0.88. Reserve ≥0.90 ONLY when the visual evidence displays unambiguous diagnostic features that visibly exclude all similar species.";
const originalDescription =
  "Calibrated confidence in the primary identification (0.0–1.0). ANCHORS: ≥0.95 = key diagnostic features are unambiguously visible in the visual evidence AND no visually confusable species shares those exact features in the same region and season; 0.80–0.94 = confident but one or more similar species cannot be definitively ruled out from the visual evidence alone; 0.60–0.79 = probable identification, multiple visually similar species remain plausible; <0.60 = uncertain, visual evidence lacks sufficient diagnostic detail for reliable species-level identification. CRITICAL: base confidence ONLY on morphological features visible in the visual evidence. NEVER inflate it because a species is locally common, seasonally expected, or habitat-appropriate — those factors resolve the primary identification but do not raise confidence. Most field photographs of common species warrant a score of 0.70–0.88.";

export function openAIConfidenceInstructions(baseline: string): string {
  if (baseline.split(originalInstruction).length !== 2) {
    throw new Error("openai_confidence_baseline_drift");
  }
  return baseline.replace(
    originalInstruction,
    "- **Confidence Scoring:** " + OPENAI_PHOTO_CONFIDENCE_RULE,
  )
    .replace(
      "# Disambiguation & Confidence Calibration",
      "# Disambiguation & Confidence Estimation",
    );
}

export function openAIConfidenceSchema(baseline: OpenAISchema): OpenAISchema {
  const confidence = baseline.properties?.confidence_score;
  if (
    !confidence || confidence.type !== "number" ||
    confidence.description !== originalDescription
  ) {
    throw new Error("openai_confidence_schema_drift");
  }
  return {
    ...baseline,
    properties: {
      ...baseline.properties,
      confidence_score: {
        ...confidence,
        description: OPENAI_PHOTO_CONFIDENCE_RULE,
      },
    },
  };
}

/** Separate evaluation authority; never accepted by active production admission. */
export function openAIConfidenceSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoSnapshot(request, 1),
    binding: "openai_photo_confidence_evaluation_v1" as const,
    contextKind: "evaluation" as const,
    prompt: OPENAI_PHOTO_CONFIDENCE_PROMPT,
  });
}

/** Exactly the production photo request plus the reviewed confidence delta. */
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
  const baseline = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  return {
    ...baseline,
    instructions: openAIConfidenceInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        schema: openAIConfidenceSchema(baseline.text.format.schema),
      },
    },
  };
}
