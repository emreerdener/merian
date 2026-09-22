import {
  parseMerianAudioIdentification,
  parseMerianIdentification,
} from "./contract.ts";
import type { ClientPayload, MerianIdentification } from "./types.ts";
import {
  type AudioSubjectKind,
  canonicalizeStructuredHumanSubject,
  normalizeAudioOnlySubject,
} from "./audioSubjectPolicy.ts";
import { normalizeProcessedMaterialSubject } from "./subjectClassification.ts";
import {
  sanitizeLifeStage,
  sanitizeObservationConfidence,
  sanitizeObservationEvidence,
  sanitizeReproductiveCondition,
  sanitizeSex,
} from "./context.ts";
import { diagnosticTriggerForTier } from "./thresholds.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizePetIdentification,
  sanitizeScientificName,
} from "../../identify/sanitize.ts";

/** Facts about the evidence actually submitted, not capture or user identity. */
export interface IdentificationNormalizationContext {
  readonly hasVisualEvidence: boolean;
  readonly hasAudioEvidence: boolean;
  readonly hasInvasiveLocationContext: boolean;
  readonly inferenceTier: "flash" | "pro";
}

/** In-memory diagnostics for the route's existing logger; never evaluation artifacts. */
export type IdentificationNormalizationDiagnostic =
  | {
    event:
      | "unknown_life_stage"
      | "unknown_reproductive_condition"
      | "unknown_sex";
    value: string;
  }
  | {
    event: "processed_material_demoted";
    reason: string | undefined;
    previous_common_name: string | null;
    previous_scientific_name: string | null;
  };

export interface NormalizedIdentification {
  identification: MerianIdentification & { blur_score: number };
  audioSubjectKind: AudioSubjectKind | null;
  // These retain the route's pre-hydration projection. The persisted domain
  // result keeps its candidates and does not acquire a default life stage.
  clientCandidates: ClientPayload["candidates"];
  clientLifeStage: ClientPayload["life_stage"];
  diagnostics: IdentificationNormalizationDiagnostic[];
}

/**
 * The active multimodal route's post-provider rules, also used by evaluation.
 * Parses/clones an unknown draft before mutation. No I/O, credentials, clocks,
 * quota, logging or dictionary hydration; the caller handles contract errors
 * and validates its complete, hydrated wire envelope separately.
 */
export function normalizeIdentification(
  draft: unknown,
  context: IdentificationNormalizationContext,
): NormalizedIdentification {
  const parsedData = context.hasAudioEvidence && !context.hasVisualEvidence
    ? parseMerianAudioIdentification(draft)
    : parseMerianIdentification(draft);
  const diagnostics: IdentificationNormalizationDiagnostic[] = [];

  if (parsedData.scientific_name) {
    parsedData.scientific_name = sanitizeScientificName(
      parsedData.scientific_name,
    );
    parsedData.scientific_name = canonicalizeDomesticPetScientificName(
      parsedData.scientific_name,
      parsedData.pet_identification,
      parsedData.common_name,
    );
  }
  parsedData.pet_identification = sanitizePetIdentification(
    parsedData.pet_identification,
    parsedData.scientific_name,
  );
  if (Array.isArray(parsedData.candidates)) {
    parsedData.candidates = parsedData.candidates
      .map((candidate) => ({
        ...candidate,
        scientific_name: sanitizeScientificName(candidate.scientific_name),
      }))
      .slice(0, 5);
  }
  if (Array.isArray(parsedData.extracted_visual_traits)) {
    parsedData.extracted_visual_traits = parsedData.extracted_visual_traits
      .slice(0, 10);
  }
  if (Array.isArray(parsedData.ecological_interactions)) {
    parsedData.ecological_interactions = parsedData.ecological_interactions
      .slice(0, 10);
  }
  if (
    typeof parsedData.ai_reasoning === "string" &&
    parsedData.ai_reasoning.length > 2000
  ) {
    parsedData.ai_reasoning = parsedData.ai_reasoning.slice(0, 2000);
  }
  if (parsedData.individual_count != null) {
    parsedData.individual_count =
      Number.isFinite(parsedData.individual_count) &&
        parsedData.individual_count > 0
        ? Math.min(Math.round(parsedData.individual_count), 99999)
        : undefined;
  }
  const sanitizedLifeStage = sanitizeLifeStage(parsedData.life_stage);
  if (
    parsedData.life_stage != null &&
    sanitizedLifeStage != parsedData.life_stage
  ) {
    diagnostics.push({
      event: "unknown_life_stage",
      value: parsedData.life_stage,
    });
  }
  parsedData.life_stage = sanitizedLifeStage;

  const sanitizedReproductiveCondition = sanitizeReproductiveCondition(
    parsedData.reproductive_condition,
  );
  if (
    parsedData.reproductive_condition != null &&
    sanitizedReproductiveCondition != parsedData.reproductive_condition
  ) {
    diagnostics.push({
      event: "unknown_reproductive_condition",
      value: parsedData.reproductive_condition,
    });
  }
  parsedData.reproductive_condition = sanitizedReproductiveCondition;

  const sanitizedSex = sanitizeSex(parsedData.sex);
  if (parsedData.sex != null && sanitizedSex != parsedData.sex) {
    diagnostics.push({
      event: "unknown_sex",
      value: parsedData.sex,
    });
  }
  parsedData.sex = sanitizedSex;
  parsedData.sex_confidence = sanitizeObservationConfidence(
    parsedData.sex_confidence,
  );
  parsedData.sex_evidence = sanitizeObservationEvidence(
    parsedData.sex_evidence,
  );
  parsedData.invasive_status_region = sanitizeObservationEvidence(
    parsedData.invasive_status_region,
    160,
  );
  parsedData.invasive_rationale = sanitizeObservationEvidence(
    parsedData.invasive_rationale,
    500,
  );
  parsedData.invasive_confidence = sanitizeObservationConfidence(
    parsedData.invasive_confidence,
  );
  const processedMaterialNormalization = normalizeProcessedMaterialSubject(
    parsedData,
  );
  if (processedMaterialNormalization.demoted) {
    diagnostics.push({
      event: "processed_material_demoted",
      reason: processedMaterialNormalization.reason,
      previous_common_name: processedMaterialNormalization.previousCommonName ??
        null,
      previous_scientific_name:
        processedMaterialNormalization.previousScientificName ?? null,
    });
  }
  let audioSubjectKind: AudioSubjectKind | null = null;
  if (context.hasAudioEvidence) {
    if (!context.hasVisualEvidence) {
      audioSubjectKind = normalizeAudioOnlySubject(parsedData);
    } else if (canonicalizeStructuredHumanSubject(parsedData)) {
      audioSubjectKind = "human";
    }
  }
  if (!parsedData.is_biological_subject) {
    parsedData.is_invasive = undefined;
    parsedData.invasive_status_region = undefined;
    parsedData.invasive_rationale = undefined;
    parsedData.invasive_confidence = undefined;
    parsedData.sex = undefined;
    parsedData.sex_confidence = undefined;
    parsedData.sex_evidence = undefined;
  } else if (
    parsedData.sex == null ||
    parsedData.sex === "cannot_determine" ||
    parsedData.sex === "not_applicable"
  ) {
    parsedData.sex_confidence = undefined;
    parsedData.sex_evidence = undefined;
  }
  if (
    parsedData.is_biological_subject &&
    audioSubjectKind !== "human" &&
    audioSubjectKind !== "unidentified_wildlife" &&
    !context.hasInvasiveLocationContext
  ) {
    parsedData.is_invasive = false;
    parsedData.invasive_status_region ??= "Unavailable";
    parsedData.invasive_rationale ??=
      "Location context was unavailable, so Naturebook could not make a region-specific invasive assessment.";
    parsedData.invasive_confidence = undefined;
  }

  parsedData.blur_score = Math.max(
    0,
    (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10,
  );

  return {
    identification: { ...parsedData, blur_score: parsedData.blur_score },
    audioSubjectKind,
    clientCandidates: (parsedData.confidence_score ?? 0.0) >=
        diagnosticTriggerForTier(context.inferenceTier)
      ? null
      : parsedData.candidates,
    clientLifeStage: parsedData.is_biological_subject &&
        audioSubjectKind !== "human" &&
        audioSubjectKind !== "unidentified_wildlife"
      ? parsedData.life_stage ?? "unknown"
      : undefined,
    diagnostics,
  };
}
