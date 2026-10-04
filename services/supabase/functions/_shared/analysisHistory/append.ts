import { parseCapturedMediaWireV1 } from "../capturedMediaContract.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import {
  HISTORY_MAX_RESULT_BYTES,
  historyUUID,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";

/** A trusted dictionary lookup, rechecked by the database before insertion. */
export interface ResolvedAnalysisSpecies {
  id: string;
  scientific_name: string;
}

/**
 * Prepared storage input, not an HTTP body or a funded completion receipt.
 * No live route calls this V1 description-only builder. Protected photos use the
 * distinct V2 manifest owner. Both private completion paths share canonical
 * Identify validation and atomically append through the funding owner.
 */
export function buildObservationAnalysisAppend(
  identity: unknown,
  resultData: unknown,
  capturedMedia: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  const binding = parseAnalysisIdentity(identity);
  const result = buildCanonicalAnalysisResult(
    binding.observation_id,
    resultData,
    species,
  );
  const media = parseCapturedMediaWireV1(capturedMedia);
  if (media.length === 0 || media.some((item) => !("description" in item))) {
    return invalidHistory();
  }
  // Canonical parsing strips review/entitlement and unknown caller fields.
  // Restore only the independently resolved, database-verified species link.
  const request = {
    ...binding,
    result_snapshot: result,
    evidence_manifest: { schema_version: 1, captured_media: media },
  };
  // Reserve space for server ordinal/completion metadata. SQL enforces the
  // exact final JSONB serialization limit, including whitespace and escaping.
  if (
    new TextEncoder().encode(JSON.stringify(request)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return Object.freeze(request);
}

/** Shared semantic owner for description and protected-photo completion. */
export function buildCanonicalAnalysisResult(
  observationID: string,
  resultData: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  const result = parseIdentifySuccessEnvelope({
    success: true,
    data: resultData,
  }).data;
  if (result.scan_id !== observationID) return invalidHistory();
  const resolution = result.primary_identification?.resolution;
  const needsSpecies = result.is_biological_subject &&
    (resolution === "species" ||
      (resolution === undefined && Boolean(result.scientific_name?.trim())));
  if (needsSpecies !== (species !== null)) return invalidHistory();
  if (species !== null) {
    historyUUID(species.id);
    if (
      typeof species.scientific_name !== "string" ||
      species.scientific_name.trim().toLowerCase() !==
        result.scientific_name?.trim().toLowerCase()
    ) return invalidHistory();
  }
  return { ...result, species_id: species?.id ?? null };
}
