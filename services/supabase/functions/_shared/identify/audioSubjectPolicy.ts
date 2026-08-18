import type { AudioProviderSubjectType } from "./contract.ts";

export const HUMAN_COMMON_NAME = "Human";
export const HUMAN_SCIENTIFIC_NAME = "Homo sapiens";
export const UNIDENTIFIED_WILDLIFE_COMMON_NAME = "Unidentified Wildlife";
export const NO_WILDLIFE_DETECTED_COMMON_NAME = "No Wildlife Detected";

export const AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION =
  `# Audio Subject Selection
First classify the recording in the required private audio_subject_type field:
- identified_non_human: a non-human animal is confidently present and its taxon is resolved.
- unidentified_non_human: a non-human animal is confidently present but its taxon is unresolved.
- human_only: unmistakable human biological sound is present and no non-human animal is confidently present.
- no_confident_biological_source: silence, handling, weather, mechanical, or indeterminate audio.

Evaluate the recording in this exact priority order:
1. A confidently detected non-human animal sound is the primary subject, including wildlife, pets, and livestock. It takes precedence over human speech, breathing, coughing, or other human sounds in the same recording.
2. If a non-human animal is confidently present but its species cannot be resolved, return is_biological_subject=true, common_name="Unidentified Wildlife", omit scientific_name, and return an empty candidates array. Do not fall back to Human merely because human sound is also present.
3. If no non-human animal is confidently present but unmistakable human biological sound is present, return is_biological_subject=true, common_name="Human", scientific_name="Homo sapiens", sex="not_applicable", and an empty candidates array. Human biological sound includes speech, breathing, coughing, and snoring; handling noise alone does not qualify.
4. For silence, handling noise, weather, mechanical sound, or otherwise indeterminate evidence, return is_biological_subject=false, common_name="No Wildlife Detected", omit scientific_name and all biology-only fields, and return an empty candidates array.

For an identified non-human animal, retain the normal species name and acoustically plausible alternative candidates. confidence_score is confidence in the returned primary classification; species uncertainty must not erase a confident non-human animal-presence determination. Never infer human sex or gender.`;

export const BLENDED_AUDIO_SUBJECT_PRECEDENCE_INSTRUCTION =
  `# Acoustic Subject Precedence
Within the audio evidence, a confidently detected non-human animal sound—including wildlife, pets, or livestock—takes precedence over human sound. If non-human animal presence is confident but the species is unresolved, describe it as Unidentified Wildlife rather than Human. Human may be the acoustic subject only when no non-human animal is confidently present. Preserve the existing cross-modal visual-versus-audio arbitration; this rule orders acoustic sources and does not make human background sound override a diagnostic visual subject.`;

export type AudioSubjectKind =
  | "identified_non_human"
  | "human"
  | "unidentified_wildlife"
  | "non_biological";

export interface AudioSubjectResult {
  audio_subject_type?: AudioProviderSubjectType | null;
  is_biological_subject: boolean;
  is_live_capture?: boolean;
  scientific_name?: string | null;
  common_name?: string | null;
  ecology_type?: string | null;
  is_invasive?: boolean | null;
  invasive_status_region?: string | null;
  invasive_rationale?: string | null;
  invasive_confidence?: number | null;
  life_stage?: string | null;
  reproductive_condition?: string | null;
  sex?: string | null;
  sex_confidence?: number | null;
  sex_evidence?: string | null;
  individual_count?: number | null;
  ecological_interactions?: unknown[] | null;
  pet_identification?: unknown | null;
  candidates?: unknown[] | null;
}

const HUMAN_SCIENTIFIC_ALIASES = new Set([
  "homo sapiens",
  "homo sapien",
]);

const HUMAN_COMMON_ALIASES = new Set([
  "human",
  "humans",
  "human being",
  "person",
  "homo sapiens",
  "homo sapien",
  "human breathing",
  "human speech",
  "human vocalisation",
  "human vocalization",
]);

const UNRESOLVED_SCIENTIFIC_NAMES = new Set([
  "unknown",
  "unknown subject",
  "taxonomy unavailable",
  "not applicable",
  "n/a",
  "unidentified wildlife",
  "no wildlife detected",
]);

/**
 * Canonicalizes a structured Human identity without reading model reasoning.
 * A resolved non-human scientific name wins over a conflicting Human common
 * name, preserving the audio precedence contract.
 */
export function canonicalizeStructuredHumanSubject(
  data: AudioSubjectResult,
): boolean {
  const scientificName = normalizedIdentity(data.scientific_name);
  const commonName = normalizedIdentity(data.common_name);
  const hasHumanScientificName = HUMAN_SCIENTIFIC_ALIASES.has(scientificName);
  const hasResolvedNonHumanScientificName = scientificName.length > 0 &&
    !hasHumanScientificName &&
    !UNRESOLVED_SCIENTIFIC_NAMES.has(scientificName);

  if (
    !hasHumanScientificName &&
    (hasResolvedNonHumanScientificName || !HUMAN_COMMON_ALIASES.has(commonName))
  ) {
    return false;
  }

  data.is_biological_subject = true;
  data.is_live_capture = true;
  data.common_name = HUMAN_COMMON_NAME;
  data.scientific_name = HUMAN_SCIENTIFIC_NAME;
  clearTaxonomyDependentFields(data);
  data.ecology_type = "unknown";
  data.sex = "not_applicable";
  return true;
}

/**
 * Normalizes the four supported audio-only result states using structured
 * output fields only. Model reasoning is intentionally not an input.
 */
export function normalizeAudioOnlySubject(
  data: AudioSubjectResult,
): AudioSubjectKind {
  const providerSubjectType = data.audio_subject_type;
  delete data.audio_subject_type;

  switch (providerSubjectType) {
    case "human_only":
      normalizeHumanSubject(data);
      return "human";
    case "unidentified_non_human":
      normalizeUnidentifiedWildlife(data);
      return "unidentified_wildlife";
    case "no_confident_biological_source":
      normalizeNonBiologicalAudio(data);
      return "non_biological";
    case "identified_non_human":
      // The presence decision remains non-human even when the provider failed
      // to supply a usable taxon. Degrade to unresolved wildlife, never Human.
      if (!hasResolvedNonHumanScientificName(data.scientific_name)) {
        normalizeUnidentifiedWildlife(data);
        return "unidentified_wildlife";
      }
      normalizeIdentifiedNonHuman(data);
      return "identified_non_human";
  }

  if (canonicalizeStructuredHumanSubject(data)) {
    return "human";
  }

  if (!data.is_biological_subject) {
    normalizeNonBiologicalAudio(data);
    return "non_biological";
  }

  if (!hasResolvedScientificName(data.scientific_name)) {
    normalizeUnidentifiedWildlife(data);
    return "unidentified_wildlife";
  }

  normalizeIdentifiedNonHuman(data);

  return "identified_non_human";
}

function normalizeIdentifiedNonHuman(data: AudioSubjectResult): void {
  data.is_biological_subject = true;
  data.is_live_capture = true;
  const commonName = normalizedIdentity(data.common_name);
  if (
    !commonName ||
    HUMAN_COMMON_ALIASES.has(commonName) ||
    UNRESOLVED_SCIENTIFIC_NAMES.has(commonName)
  ) {
    // The scientific name is a safe display fallback when the provider omits
    // a common name or contradicts the selected non-human taxon with Human.
    data.common_name = data.scientific_name;
  }
}

function normalizeHumanSubject(data: AudioSubjectResult): void {
  data.is_biological_subject = true;
  data.is_live_capture = true;
  data.common_name = HUMAN_COMMON_NAME;
  data.scientific_name = HUMAN_SCIENTIFIC_NAME;
  clearTaxonomyDependentFields(data);
  data.ecology_type = "unknown";
  data.sex = "not_applicable";
}

function normalizeUnidentifiedWildlife(data: AudioSubjectResult): void {
  data.is_biological_subject = true;
  data.is_live_capture = true;
  data.common_name = UNIDENTIFIED_WILDLIFE_COMMON_NAME;
  data.scientific_name = undefined;
  clearTaxonomyDependentFields(data);
}

function normalizeNonBiologicalAudio(data: AudioSubjectResult): void {
  data.is_biological_subject = false;
  data.is_live_capture = false;
  data.common_name = NO_WILDLIFE_DETECTED_COMMON_NAME;
  data.scientific_name = undefined;
  clearTaxonomyDependentFields(data);
}

function clearTaxonomyDependentFields(data: AudioSubjectResult): void {
  data.ecology_type = undefined;
  data.is_invasive = undefined;
  data.invasive_status_region = undefined;
  data.invasive_rationale = undefined;
  data.invasive_confidence = undefined;
  data.life_stage = undefined;
  data.reproductive_condition = undefined;
  data.sex = undefined;
  data.sex_confidence = undefined;
  data.sex_evidence = undefined;
  data.individual_count = undefined;
  data.ecological_interactions = undefined;
  data.pet_identification = null;
  data.candidates = [];
}

function hasResolvedScientificName(value: unknown): boolean {
  const normalized = normalizedIdentity(value);
  return normalized.length > 0 && !UNRESOLVED_SCIENTIFIC_NAMES.has(normalized);
}

function hasResolvedNonHumanScientificName(value: unknown): boolean {
  const normalized = normalizedIdentity(value);
  return normalized.length > 0 &&
    !HUMAN_SCIENTIFIC_ALIASES.has(normalized) &&
    !UNRESOLVED_SCIENTIFIC_NAMES.has(normalized);
}

function normalizedIdentity(value: unknown): string {
  return typeof value === "string"
    ? value.toLowerCase().replace(/\s+/g, " ").trim()
    : "";
}
