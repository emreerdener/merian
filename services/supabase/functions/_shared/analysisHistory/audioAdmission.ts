import { parsePreparedAudioManifest } from "./audioManifest.ts";
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

const inputKeys = [
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
] as const;

/** Closed audio metadata. SQL separately binds receipts and runtime gates.
 * Readiness, current consent and the audio quota profile remain server checks.
 */
export function parsePreparedAudioAdmission(value: unknown) {
  const row = exactObject(value, inputKeys);
  if (
    row.schema_version !== 3 || row.entitlement_protocol !== 3 ||
    row.identification_protocol !== 6 || row.history_protocol !== 9 ||
    row.expected_processor_permission !== "google_gemini"
  ) return invalidHistory();
  const identity = parseAnalysisIdentity({
    schema_version: 1,
    observation_id: row.observation_id,
    analysis_id: row.analysis_id,
    source_analysis_id: row.source_analysis_id,
    request_digest: row.request_digest,
  });
  const evidence = parsePreparedAudioManifest(
    row.evidence_manifest,
    identity.observation_id,
    identity.analysis_id,
  );
  // A child owns its new media IDs; none may alias a historical source identity.
  if (
    evidence.items.some((item) =>
      item.kind === "audio" && item.media_id === identity.source_analysis_id
    )
  ) return invalidHistory();
  const input = Object.freeze({
    ...identity,
    schema_version: 3 as const,
    evidence_manifest: evidence,
    entitlement_protocol: 3 as const,
    identification_protocol: 6 as const,
    history_protocol: 9 as const,
    expected_processor_permission: "google_gemini" as const,
  });
  checkSize(input);
  return input;
}

/** Canonicalize only newly prepared input. Never rewrite a saved V2 request. */
export function buildPreparedAudioAdmission(value: unknown): string {
  return JSON.stringify(parsePreparedAudioAdmission(value));
}

/** Exact persisted input is revalidated, not rebuilt from live parent data.
 * This draft is not a result-4 snapshot, funded receipt or append authorization.
 */
export function buildPreparedAudioDraft(
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
  const input = parsePreparedAudioAdmission(value);
  const draft = Object.freeze({
    schema_version: 3 as const,
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
  checkSize(draft);
  return draft;
}

function checkSize(value: unknown): void {
  if (
    new TextEncoder().encode(JSON.stringify(value)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
}
