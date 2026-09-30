/** Candidate-only evidence limits; production and historical prompts stay frozen. */
export const OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE =
  "openai_photo_luna_evidence_limits_low_v1" as const;
export const OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT =
  "openai_identify_vision_evidence_limits_v1" as const;
export const OPENAI_LUNA_EVIDENCE_LIMITS_PROMPT_DIGEST =
  "58d79c33674e0a3467a1408080b07634ec0a97fd9aa802dbacc4d3c229b40bfd";
const edits = [
  [
    "For geological subjects (rocks, minerals), you MUST still provide `common_name` and `scientific_name` if identifiable. Omit these for generic debris and manufactured/processed objects.",
    'For geological subjects (rocks, minerals), a specific mineral name requires evidence that distinguishes it from plausible alternatives. Color, shape, or crystal-like appearance alone do not establish mineral composition, origin, treatment, or gemstone identity. Without distinguishing evidence, use a broad `common_name` such as "Mineral Specimen", omit `scientific_name`, and mention a plausible identity in `ai_reasoning` only as a possibility. If identifiable from the supplied evidence, provide `common_name` and `scientific_name`. Keep result names and explanatory claims consistent with the same evidence limit: uncertainty about a variety does not establish the broader mineral identity. Never imply that tests or provenance were supplied when they were not. Omit these fields for generic debris and manufactured/processed objects.',
  ],
  [
    "`common_name` must be maximally specific in Title Case.",
    "`common_name` must be maximally specific in Title Case. For non-biological subjects, use only the specificity supported by the supplied evidence; the Geological Exceptions rule takes precedence over a more specific name.",
  ],
] as const;

export function openAILunaEvidenceLimitsInstructions(baseline: string): string {
  let instructions = baseline;
  for (const [before, after] of edits) {
    if (instructions.split(before).length !== 2) {
      throw new Error("openai_prompt_revision_mismatch");
    }
    instructions = instructions.replace(before, after);
  }
  return instructions;
}
