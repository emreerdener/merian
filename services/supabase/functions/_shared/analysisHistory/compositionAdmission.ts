import {
  buildCanonicalAnalysisResult,
  type ResolvedAnalysisSpecies,
} from "./append.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";
import { parseCompositionManifest } from "./compositionManifest.ts";

/** Prepared composition contract, not a funded admission or a dispatch grant.
 * Existing persisted V2/V3/V4 inputs retain their exact bytes and validators.
 */
export function parseCompositionAdmission(value: unknown) {
  return parseAdmission(value, 5);
}

/** Successor codec only. Live V5 callers do not opt into V6 admission. */
export function parseFocusedCompositionRequestStructure(value: unknown) {
  return parseAdmission(value, 6);
}

/** Closed version dispatcher. Structure alone grants no execution authority;
 * V6 boundaries must also validate its typed request digest. */
export function parseCompositionRequestStructure(value: unknown) {
  if (
    value !== null && typeof value === "object" &&
    "schema_version" in value && value.schema_version === 6
  ) {
    return parseFocusedCompositionRequestStructure(value);
  }
  return parseCompositionAdmission(value);
}
export type CompositionRequest = ReturnType<
  typeof parseCompositionRequestStructure
>;

function parseAdmission<V extends 5 | 6>(value: unknown, version: V) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "evidence_manifest",
    "entitlement_protocol",
    "identification_protocol",
    "history_protocol",
    "expected_processor_permission",
  ]);
  if (
    row.schema_version !== version || row.entitlement_protocol !== 3 ||
    row.identification_protocol !== 7 || row.history_protocol !== 10 ||
    row.expected_processor_permission !== "google_gemini"
  ) return invalidHistory();
  const identity = parseAnalysisIdentity({
    schema_version: 1,
    observation_id: row.observation_id,
    analysis_id: row.analysis_id,
    source_analysis_id: row.source_analysis_id,
    request_digest: row.request_digest,
  });
  if (identity.source_analysis_id === null) return invalidHistory();
  const manifest = parseCompositionManifest(
    row.evidence_manifest,
    identity.observation_id,
    identity.analysis_id,
    identity.source_analysis_id,
  );
  // V6 metadata is independently readable but must not enter the V5 execution
  // contract. Its admission and result generations are coordinated separately.
  if (manifest.schema_version !== row.schema_version) return invalidHistory();
  const input = Object.freeze({
    ...identity,
    source_analysis_id: identity.source_analysis_id,
    schema_version: version,
    evidence_manifest: manifest,
    entitlement_protocol: 3 as const,
    identification_protocol: 7 as const,
    history_protocol: 10 as const,
    expected_processor_permission: "google_gemini" as const,
  });
  if (
    new TextEncoder().encode(JSON.stringify(input)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return input;
}

export type CompositionAdmission = ReturnType<typeof parseCompositionAdmission>;

/** Canonical saved V5 draft, with the complete ordered manifest. No live append
 * or current-selection authority is granted by preparing these bytes. */
export function buildCompositionDraft(
  inputBytes: string,
  result: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  if (
    typeof inputBytes !== "string" ||
    new TextEncoder().encode(inputBytes).length > HISTORY_MAX_RESULT_BYTES
  ) return invalidHistory();
  let value: unknown;
  try {
    value = JSON.parse(inputBytes);
  } catch {
    return invalidHistory();
  }
  const input = parseCompositionRequestStructure(value);
  const draft = Object.freeze({
    schema_version: input.schema_version,
    observation_id: input.observation_id,
    analysis_id: input.analysis_id,
    source_analysis_id: input.source_analysis_id,
    request_digest: input.request_digest,
    evidence_manifest: input.evidence_manifest,
    result_snapshot: buildCanonicalAnalysisResult(
      input.observation_id,
      result,
      species,
    ),
  });
  if (
    new TextEncoder().encode(JSON.stringify(draft)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return draft;
}
