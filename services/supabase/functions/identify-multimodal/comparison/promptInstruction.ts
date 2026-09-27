import { BIOACOUSTIC_SYSTEM_INSTRUCTION } from "../instructions.ts";

export const AUDIO_UNCERTAINTY_PROMPT =
  "identify_audio_uncertainty_experiment_v1";
export const AUDIO_UNCERTAINTY_INSTRUCTION_DELTA =
  "# Species evidence check\nBefore choosing identified_non_human, require audible features that distinguish the proposed species from other plausible animals. Familiarity with a call, a best guess, clarity, repetition, or geographic plausibility alone is insufficient.\nWhen non-human animal presence is confident but the recording does not distinguish among plausible species, choose unidentified_non_human even if one species seems most likely. Use the existing Unidentified Wildlife fields, omit scientific_name, and return no candidates. Do not turn clear animal presence into a non-biological result to avoid naming a species.\nWhen the recording does distinguish a species, retain identified_non_human and score that identity using the existing Audio Confidence definition. Preserve the existing Human and non-biological precedence and response rules. Return only the existing JSON structure; do not add fields.";

/** Named instruction only; callers cannot replace schema, evidence or settings. */
export function audioUncertaintySystemInstruction(): string {
  const marker = "# Response Detail Rules";
  if (BIOACOUSTIC_SYSTEM_INSTRUCTION.split(marker).length !== 2) {
    throw new Error("audio_prompt_instruction_drift");
  }
  return BIOACOUSTIC_SYSTEM_INSTRUCTION.replace(
    marker,
    AUDIO_UNCERTAINTY_INSTRUCTION_DELTA + "\n\n" + marker,
  );
}
