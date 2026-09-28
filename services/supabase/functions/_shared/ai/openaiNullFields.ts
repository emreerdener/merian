/** OpenAI-only wording projection. Shared instructions and old profiles stay frozen. */
export const OPENAI_NULL_FIELDS_PROFILE =
  "openai_photo_null_fields_v1" as const;
export const OPENAI_NULL_FIELDS_PROMPT =
  "openai_identify_vision_null_fields_v1" as const;
export const OPENAI_NULL_FIELDS_PROMPT_DIGEST =
  "8d8c5ab7f612555a0a275ade42de7615f327314c644502ab5d2217c1bab1f948";
export const OPENAI_NULL_FIELDS_SCHEMA_DIGEST =
  "bda80368f8be0ef9424e22b7f7adfa1c7ecc5098ff68c9e52bc4c8f69182e52e";
const edits = [
  ["and omit `scientific_name`.", "and set `scientific_name` to null."],
  [
    "Omit these for generic debris and manufactured/processed objects.",
    "Set these fields to null for generic debris and manufactured/processed objects.",
  ],
  [
    "you MUST omit `scientific_name`.",
    "you MUST set `scientific_name` to null.",
  ],
  [
    "All non-biological results MUST omit:",
    "All non-biological results MUST set the following fields to null:",
  ],
] as const;
export function openAINullFieldsInstructions(baseline: string): string {
  let instructions = baseline;
  for (const [before, after] of edits) {
    if (instructions.split(before).length !== 2) {
      throw new Error("openai_prompt_revision_mismatch");
    }
    instructions = instructions.replace(before, after);
  }
  return instructions;
}
