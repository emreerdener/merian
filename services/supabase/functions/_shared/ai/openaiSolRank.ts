/** Evaluator-only Sol guidance. Production catalog and result bindings reject it. */
import type { AIRequest } from "./contracts.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import type { OpenAISchema } from "./openaiRequest.ts";

export const SOL_RANK_PROFILE = "openai_photo_sol_rank_limits_low_v1" as const;
export const SOL_RANK_PROMPT = "openai_identify_vision_rank_limits_v1" as const;
export const SOL_RANK_SCHEMA = "merian_openai_identify_rank_v1" as const;

const instructionEdits = [
  [
    "when not alive — identify these to the species level.",
    "when not alive — identify these to the most specific rank supported by the supplied visual evidence.",
  ],
  [
    "\u0060common_name\u0060 must be maximally specific in Title Case.",
    "\u0060common_name\u0060 must be maximally specific in Title Case. For biological subjects, specificity must match the supported scientific rank: use a group name for a genus or family result, not the common name of one possible species.",
  ],
  [
    '\u0060scientific_name\u0060 MUST be the currently accepted binomial recognized by GBIF, ITIS, or Catalogue of Life.\n   - Never return author citations (e.g., omit "(Linnaeus, 1758)"), hybrid markers (×), or infraspecific ranks unless it is the minimal determinate rank (e.g., *Brassica oleracea var. italica*).\n   - Return a genus-level name alone (without "sp.") ONLY when species determination is impossible. Never fabricate names.',
    'For biological subjects, \u0060scientific_name\u0060 must use an accepted name at the most specific supported rank. Use a binomial only when the supplied visual evidence distinguishes that species from plausible lookalikes. If it supports only a genus or family, return that genus or family name alone, without "sp.". If none of these ranks can be supported, return null and explain the limitation.\n   - Never fabricate names or include author citations or hybrid markers (×). Use an infraspecific name only when distinguishing evidence supports that rank.\n   - Preserve a species identification when diagnostic evidence supports it; uncertainty is not a reason to reduce every result to a broader rank. Geological naming continues to follow Geological Exceptions.',
  ],
  [
    "When multiple species are visually equally plausible, use GPS location and current month as a tiebreaker. Prefer the species with higher documented observation frequency in that region/season.",
    "Use only supplied location and month context, and only within the rank supported by visual evidence. Regional frequency, season, or popularity cannot replace a missing diagnostic feature or turn a genus-level observation into a species identification. Never invent locality or distribution evidence.",
  ],
  [
    "Express genuine uncertainty through a lower \u0060confidence_score\u0060 and populated \u0060candidates\u0060 array rather than hallucinating or alternating primary identifications.",
    "Keep the primary scientific name, common name, alternatives, and explanation consistent with the same evidence limit. A lower \u0060confidence_score\u0060 or a disclaimer cannot justify an unsupported species name. Missing, obscured, or unphotographed features are unknown, not absent. State observed support and any missing diagnostic evidence in the existing explanation format.",
  ],
  [
    "For biological subjects, you MUST populate exactly 2 alternative species in the \u0060candidates\u0060 array. For non-biological subjects, use an empty \u0060candidates\u0060 array.",
    "For biological subjects, include zero to two evidence-supported alternatives in the \u0060candidates\u0060 array. Keep alternatives within the supported rank; do not force species alternatives for a genus, family, or unresolved result. Use an empty array when no useful alternative can be supported. For non-biological subjects, use an empty \u0060candidates\u0060 array.",
  ],
  [
    "Choose candidates that share the most traits from \u0060extracted_visual_traits\u0060 with the primary ID. Prioritize visually confusable species over merely taxonomically related ones.",
    "Choose visually confusable alternatives grounded in observed traits, not merely taxonomically related names. Do not invent alternatives to fill the array.",
  ],
  [
    'For each candidate, provide the single most important observable morphological difference that separates it from your primary ID. State this as a concise clause referencing a specific visible trait (e.g., "cap margin lacks striations present on primary"). Do NOT repeat the species name here.',
    "For each candidate, state a specific observed distinction, or explicitly name the additional distinguishing feature that would need to be seen. Do not describe an unseen feature as absent or claim it was observed. Keep one concise clause without repeating the taxon name.",
  ],
] as const;

function replaceOnce(value: string, before: string, after: string): string {
  if (value.split(before).length !== 2) {
    throw new Error("sol_rank_candidate_baseline_drift");
  }
  return value.replace(before, after);
}

export function solPhotoRankInstructions(baseline: string): string {
  return instructionEdits.reduce(
    (value, [before, after]) => replaceOnce(value, before, after),
    baseline,
  );
}

/** Description-only projection: JSON shape and common-contract decoding stay fixed. */
export function solPhotoRankSchema(baseline: OpenAISchema): OpenAISchema {
  const schema = structuredClone(baseline);
  const p = schema.properties;
  if (!p) throw new Error("sol_rank_candidate_baseline_drift");
  const edits: [OpenAISchema | undefined, string, string][] = [
    [
      p.scientific_name,
      "Formally accepted binomial scientific name. Required for biological subjects and identifiable geological specimens. Null for manufactured, processed, or unidentifiable non-natural objects.",
      "For biological subjects, the accepted name at the most specific visually supported rank: species only with diagnostic evidence, otherwise genus or family, or null when no such rank is supported. No author citations or fabricated names. Geological specimens and other non-biological subjects follow the unchanged Geological Exceptions and Conditional Formatting rules.",
    ],
    [
      p.common_name,
      "Most specific, commonly recognized English name in Title Case. Null for unidentifiable non-natural objects.",
      "Most specific, commonly recognized English name in Title Case. For biological subjects, match the supported scientific rank and use a group name for genus or family results. Do not imply a species through its common name when that species is unsupported. Null for unidentifiable non-natural objects.",
    ],
    [
      p.candidates,
      "For biological subjects, provide exactly 2 alternative species candidates grounded in the extracted_visual_traits. For non-biological subjects, return an empty array. Choose candidates that share the most observed traits with the primary identification — not just taxonomically related species. For each, distinguishing_feature must name the specific observable difference that rules it in or out.",
      "For biological subjects, zero to two evidence-supported, visually confusable alternatives within the supported rank; do not force species alternatives for genus, family, or unresolved results. Return an empty array when none is supportable, and for all non-biological subjects. Never invent names to fill the array.",
    ],
    [
      p.candidates?.items?.properties?.distinguishing_feature,
      "The single most important visual feature that separates this candidate from the primary identification. Must reference a specific trait from extracted_visual_traits or a directly observable morphological difference (e.g. 'cap margin lacks striations', 'wing bars absent', 'leaf base asymmetric'). One concise clause — do not repeat the species name.",
      "One concise clause naming a specific observed distinction, or explicitly the additional distinguishing feature that would need to be seen. Unseen features are unknown, not absent. Do not invent observations or repeat the taxon name.",
    ],
  ];
  for (const [node, before, after] of edits) {
    if (!node || node.description !== before) {
      throw new Error("sol_rank_candidate_baseline_drift");
    }
    node.description = after;
  }
  return schema;
}

export function solPhotoRankSnapshot(request: AIRequest) {
  return Object.freeze({
    ...openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
    binding: "openai_sol_rank_evaluation_v1" as const,
    profile: SOL_RANK_PROFILE,
    prompt: SOL_RANK_PROMPT,
    schema: SOL_RANK_SCHEMA,
  });
}

export function buildSolPhotoRankRequest(
  request: AIRequest,
  snapshot: ReturnType<typeof solPhotoRankSnapshot>,
) {
  if (
    JSON.stringify(snapshot) !== JSON.stringify(solPhotoRankSnapshot(request))
  ) throw new Error("openai_binding_mismatch");
  const baseline = buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
  return {
    ...baseline,
    instructions: solPhotoRankInstructions(baseline.instructions),
    text: {
      ...baseline.text,
      format: {
        ...baseline.text.format,
        name: snapshot.schema,
        schema: solPhotoRankSchema(baseline.text.format.schema),
      },
    },
  };
}
