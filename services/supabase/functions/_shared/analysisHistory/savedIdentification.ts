import {
  identificationProvenanceContract,
  parseContract,
  parsePrimaryIdentification,
  PRIMARY_IDENTIFICATION_SCHEMA,
} from "../identify/contract.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

/** A saved server row is not a recovered Identify response or provider input. */
export function parseSavedIdentification(value: unknown, observation: string) {
  const row = exactObject(value, [
    "scan_id",
    "primary_identification",
    "identification_provenance",
    "species_id",
    "is_biological_subject",
    "candidates",
    "pet_identification",
    "ai_confidence_score",
    "ai_reasoning",
    "inference_tier",
  ]);
  if (
    historyUUID(row.scan_id) !== observation ||
    (row.is_biological_subject !== null &&
      typeof row.is_biological_subject !== "boolean") ||
    typeof row.ai_confidence_score !== "number" ||
    !Number.isFinite(row.ai_confidence_score) || row.ai_confidence_score < 0 ||
    row.ai_confidence_score > 1 ||
    (row.ai_reasoning !== null && typeof row.ai_reasoning !== "string") ||
    (row.inference_tier !== null && typeof row.inference_tier !== "string")
  ) return invalidHistory();
  if (row.species_id !== null) historyUUID(row.species_id);
  if (row.primary_identification !== null) {
    parsePrimaryIdentification(row.primary_identification);
  }
  if (row.identification_provenance !== null) {
    parseContract(
      identificationProvenanceContract,
      row.identification_provenance,
    );
  }
  const provenance = row.identification_provenance;
  const hasPrimarySchema = provenance !== null &&
    typeof provenance === "object" &&
    "schema" in provenance &&
    provenance.schema === PRIMARY_IDENTIFICATION_SCHEMA;
  if ((row.primary_identification !== null) !== hasPrimarySchema) {
    return invalidHistory();
  }
  // Legacy candidates/pet JSON predates the current Identify contract. Retain
  // it as opaque bounded data, never reinterpret it as a current provider DTO.
  // Validate without rewriting legacy facts or applying current review. The
  // caller retains exact snapshot bytes; authority travels separately.
  return row;
}

export function parseSavedHistoryEnrollment(
  value: unknown,
  ownerID: string,
  observationID: string,
) {
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "baseline_analysis_id",
  ]);
  const baseline = historyUUID(row.baseline_analysis_id);
  if (
    row.schema_version !== 1 || row.owner_id !== historyUUID(ownerID) ||
    row.observation_id !== historyUUID(observationID) ||
    [ownerID, observationID].includes(baseline)
  ) return invalidHistory();
  // This acknowledgement deliberately contains no selection or stale revision.
  // Hydrate current authority before admitting enrollment to the native store.
  return Object.freeze({
    schema_version: 1 as const,
    owner_id: ownerID,
    observation_id: observationID,
    baseline_analysis_id: baseline,
  });
}
