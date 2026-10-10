import { parsePreparedVideoManifest } from "./videoManifest.ts";
import { parsePreparedAudioManifest } from "./audioManifest.ts";
import { parseSavedIdentification } from "./savedIdentification.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";
import { parseCapturedMediaWireV1 } from "../capturedMediaContract.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  historyRevision,
  historyUUID,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";

/**
 * Validation view of immutable evidence; review and funding are excluded.
 * The Identify parser normalizes away server-only projection fields such as
 * species_id. Never persist this normalized return value as result_snapshot;
 * readers preserve the original bytes and completion must validate the separate
 * projection-ready server object against canonical Identify data and taxonomy.
 */
export function parseAnalysisResultSnapshot(value: unknown) {
  return parseSnapshot(value, false);
}

export function parseAnalysisResultSnapshotV2(value: unknown) {
  return parseSnapshot(value, true);
}

function parseSnapshot(
  value: unknown,
  allowProtected: boolean,
  allowAudio = false,
  allowVideo = false,
) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "ordinal",
    "completed_at_ms",
    "result",
    "evidence_manifest",
  ]);
  const version = row.schema_version;
  if (
    version !== 1 && !(allowProtected && version === 2) &&
    !(allowAudio && version === 4) && !(allowVideo && version === 5)
  ) {
    return invalidHistory();
  }
  const identity = parseAnalysisIdentity({
    schema_version: 1,
    observation_id: row.observation_id,
    analysis_id: row.analysis_id,
    source_analysis_id: row.source_analysis_id,
    request_digest: row.request_digest,
  });
  if (
    typeof row.completed_at_ms !== "number" ||
    !Number.isSafeInteger(row.completed_at_ms) || row.completed_at_ms < 0 ||
    row.completed_at_ms > 8_640_000_000_000_000
  ) return invalidHistory();
  const result =
    parseIdentifySuccessEnvelope({ success: true, data: row.result }).data;
  if (historyUUID(result.scan_id) !== identity.observation_id) {
    return invalidHistory();
  }
  let evidence;
  if (version === 5) {
    if (identity.source_analysis_id === null) return invalidHistory();
    evidence = parsePreparedVideoManifest(
      row.evidence_manifest,
      identity.observation_id,
      identity.analysis_id,
    );
    const graph = evidence.provenance;
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
  } else if (version === 4) {
    evidence = parsePreparedAudioManifest(
      row.evidence_manifest,
      identity.observation_id,
      identity.analysis_id,
    );
    if (
      evidence.items.some((item) =>
        item.kind === "audio" && item.media_id === identity.source_analysis_id
      )
    ) return invalidHistory();
  } else if (version === 2) {
    evidence = parseProtectedEvidenceManifest(row.evidence_manifest);
    if (
      evidence.items.some((item) =>
        item.kind === "image" &&
        [identity.observation_id, identity.analysis_id].includes(item.media_id)
      )
    ) return invalidHistory();
  } else {
    const legacy = exactObject(row.evidence_manifest, [
      "schema_version",
      "captured_media",
    ]);
    if (legacy.schema_version !== 1) return invalidHistory();
    const media = parseCapturedMediaWireV1(legacy.captured_media);
    if (!media.length) return invalidHistory();
    evidence = { schema_version: 1 as const, captured_media: media };
  }
  const ordinal = historyRevision(row.ordinal);
  if (ordinal < 1) return invalidHistory();
  const snapshot = {
    ...identity,
    schema_version: version,
    ordinal,
    completed_at_ms: row.completed_at_ms,
    result,
    evidence_manifest: evidence,
  };
  if (
    new TextEncoder().encode(JSON.stringify(snapshot)).length >
      HISTORY_MAX_RESULT_BYTES
  ) {
    return invalidHistory();
  }
  return Object.freeze(snapshot);
}

/** Validate read-back bytes. Callers retain the original text for exact replay. */
export function decodeAnalysisResultSnapshot(
  text: unknown,
  reader: 7 | 8 | 9 | 10 | 11 = 7,
) {
  if (
    (reader !== 7 && reader !== 8 && reader !== 9 && reader !== 10 &&
      reader !== 11) ||
    typeof text !== "string" ||
    new TextEncoder().encode(text).length > HISTORY_MAX_RESULT_BYTES
  ) {
    return invalidHistory();
  }
  try {
    const value = JSON.parse(text);
    if (reader >= 9 && value?.schema_version === 3) {
      return parseImportedSnapshot(value);
    }
    return parseSnapshot(value, reader >= 8, reader >= 10, reader === 11);
  } catch {
    return invalidHistory();
  }
}

/** V3 explicitly represents unavailable execution metadata; never infer it. */
function parseImportedSnapshot(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "ordinal",
    "completed_at_ms",
    "result",
    "evidence_manifest",
  ]);
  const observation = historyUUID(row.observation_id);
  const analysis = historyUUID(row.analysis_id);
  const manifest = exactObject(row.evidence_manifest, [
    "schema_version",
    "origin",
    "imported_at_ms",
    "availability",
  ]);
  if (
    row.schema_version !== 3 || row.ordinal !== 1 ||
    row.source_analysis_id !== null || row.request_digest !== null ||
    row.completed_at_ms !== null || analysis === observation ||
    manifest.schema_version !== 3 ||
    manifest.origin !== "saved_identification" ||
    manifest.availability !== "unavailable" ||
    typeof manifest.imported_at_ms !== "number" ||
    !Number.isSafeInteger(manifest.imported_at_ms) ||
    manifest.imported_at_ms < 0 ||
    manifest.imported_at_ms > 8_640_000_000_000_000
  ) return invalidHistory();
  return Object.freeze({
    schema_version: 3 as const,
    observation_id: observation,
    analysis_id: analysis,
    source_analysis_id: null,
    request_digest: null,
    ordinal: 1,
    completed_at_ms: null,
    result: parseSavedIdentification(row.result, observation),
    evidence_manifest: {
      schema_version: 3 as const,
      origin: "saved_identification" as const,
      imported_at_ms: manifest.imported_at_ms,
      availability: "unavailable" as const,
    },
  });
}
