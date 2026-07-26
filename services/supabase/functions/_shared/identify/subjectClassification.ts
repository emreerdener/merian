import type { MerianIdentification } from "./types.ts";

export interface SubjectClassificationNormalization {
  demoted: boolean;
  reason?: string;
  previousCommonName?: string;
  previousScientificName?: string;
}

const ARTIFACT_OBJECT_TERMS = [
  "rug",
  "kilim",
  "textile",
  "fabric",
  "cloth",
  "shirt",
  "jacket",
  "coat",
  "shoe",
  "bag",
  "leather goods",
  "leather jacket",
  "wool rug",
  "wool kilim",
  "wool carpet",
  "wool textile",
  "wool fabric",
  "wool yarn",
  "woolen",
  "woollen",
  "cotton textile",
  "cotton fabric",
  "cotton shirt",
  "cotton cloth",
  "linen textile",
  "linen fabric",
  "paper bag",
  "paper sheet",
  "paper print",
  "cardboard",
  "wooden",
  "furniture",
  "wooden table",
  "wooden chair",
  "wooden cabinet",
  "chair",
  "cabinet",
  "toy",
  "doll",
  "statue",
  "sculpture",
  "painting",
  "drawing",
  "print",
  "artwork",
  "ornament",
  "decoration",
  "prepared food",
];

const MATERIAL_EVIDENCE_TERMS = [
  "wool",
  "cotton",
  "paper",
  "leather",
  "linen",
  "wood",
  "wooden",
  "carpet",
  "mat",
  "food",
  "meal",
  "bread",
  "meat",
  "jerky",
  "steak",
  "burger",
  "sausage",
];

const PROCESSED_SUBJECT_TERMS = [
  "man-made",
  "man made",
  "human-made",
  "human made",
  "manufactured",
  "processed",
  "inanimate",
  "object",
  "artifact",
  "artefact",
  "woven",
  "flat-woven",
  "fabricated",
  "made from",
  "composed of processed",
  "does not represent a living organism",
  "does not represent an organism",
  "not a biological subject",
];

const PRESERVED_SPECIMEN_TERMS = [
  "fossil",
  "preserved specimen",
  "pressed specimen",
  "pressed plant",
  "herbarium",
  "taxidermy",
  "mounted specimen",
  "museum specimen",
  "dried specimen",
];

export function normalizeProcessedMaterialSubject(
  data: MerianIdentification,
): SubjectClassificationNormalization {
  if (!data.is_biological_subject) {
    clearNonBiologicalFields(data, {
      clearScientificName: isLikelyProcessedMaterialSubject(data),
    });
    return { demoted: false };
  }

  if (!isLikelyProcessedMaterialSubject(data)) {
    return { demoted: false };
  }

  const previousCommonName = data.common_name;
  const previousScientificName = data.scientific_name;
  data.is_biological_subject = false;
  data.is_live_capture = false;
  clearNonBiologicalFields(data, { clearScientificName: true });

  return {
    demoted: true,
    reason: "processed_material_or_artifact_subject",
    previousCommonName: previousCommonName ?? undefined,
    previousScientificName: previousScientificName ?? undefined,
  };
}

function clearNonBiologicalFields(
  data: MerianIdentification,
  options: { clearScientificName: boolean },
): void {
  if (options.clearScientificName) {
    data.scientific_name = undefined;
  }
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

function isLikelyProcessedMaterialSubject(
  data: MerianIdentification,
): boolean {
  const commonName = normalizeText(data.common_name);
  const reasoning = normalizeText(data.ai_reasoning);
  const traits = normalizeText(data.extracted_visual_traits?.join(" "));
  const combined = [commonName, reasoning, traits].filter(Boolean).join(" ");

  if (!combined) return false;
  if (containsAnyTerm(combined, PRESERVED_SPECIMEN_TERMS)) return false;

  const artifactNamedSubject = containsAnyTerm(
    commonName,
    ARTIFACT_OBJECT_TERMS,
  ) || matchesExactTerm(commonName, MATERIAL_EVIDENCE_TERMS);
  const modelAdmittedProcessedSubject = containsAnyTerm(
    combined,
    PROCESSED_SUBJECT_TERMS,
  );
  const artifactEvidence = containsAnyTerm(combined, ARTIFACT_OBJECT_TERMS) ||
    containsAnyTerm(combined, MATERIAL_EVIDENCE_TERMS);

  return artifactNamedSubject ||
    (modelAdmittedProcessedSubject && artifactEvidence);
}

function normalizeText(value: unknown): string {
  return typeof value === "string"
    ? value.toLowerCase().replace(/\s+/g, " ").trim()
    : "";
}

function containsAnyTerm(haystack: string, needles: string[]): boolean {
  return needles.some((needle) => termPattern(needle).test(haystack));
}

function matchesExactTerm(value: string, terms: string[]): boolean {
  return terms.includes(value.trim());
}

function termPattern(term: string): RegExp {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    .replace(/\s+/g, "\\s+");
  return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`);
}
