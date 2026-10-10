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
import { parsePreparedVideoManifest } from "./videoManifest.ts";

/** Prepared metadata contract only. Not registered with executable admission.
 * request_digest retains its existing replay-identifier meaning, not a server JSON hash proof.
 * Consent protocol 9 is independent of the future public result-reader version.
 */
export function parsePreparedVideoAdmission(value: unknown) {
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
    row.schema_version !== 4 || row.entitlement_protocol !== 3 ||
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
  if (identity.source_analysis_id === null) return invalidHistory();
  const manifest = parsePreparedVideoManifest(
    row.evidence_manifest,
    identity.observation_id,
    identity.analysis_id,
  );
  const graph = manifest.provenance;
  const artifacts = [
    graph.source,
    ...graph.frames.map((frame) => frame.artifact),
    ...(graph.audio ? [graph.audio.artifact] : []),
  ];
  if (
    artifacts.some((artifact) =>
      artifact.media_id === identity.source_analysis_id
    )
  ) return invalidHistory();
  const input = Object.freeze({
    ...identity,
    source_analysis_id: identity.source_analysis_id,
    schema_version: 4 as const,
    evidence_manifest: manifest,
    entitlement_protocol: 3 as const,
    identification_protocol: 6 as const,
    history_protocol: 9 as const,
    expected_processor_permission: "google_gemini" as const,
  });
  if (
    new TextEncoder().encode(JSON.stringify(input)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return input;
}

/** Fresh preparation only. Never use this to rewrite saved photo/audio/video bytes. */
export function buildPreparedVideoAdmission(value: unknown): string {
  return JSON.stringify(parsePreparedVideoAdmission(value));
}

/** Pure prepared storage draft from the original saved V4 input. This grants
 * no execution, append, settlement or result-reader authority. */
export function buildPreparedVideoDraft(
  inputBytes: string,
  result: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  if (
    typeof inputBytes !== "string" ||
    new TextEncoder().encode(inputBytes).length > HISTORY_MAX_RESULT_BYTES
  ) {
    return invalidHistory();
  }
  let value: unknown;
  try {
    value = JSON.parse(inputBytes);
  } catch {
    return invalidHistory();
  }
  const input = parsePreparedVideoAdmission(value);
  const draft = Object.freeze({
    schema_version: 4 as const,
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
