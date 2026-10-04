import {
  exactObject,
  historyRevision,
  historyUUID,
  invalidHistory,
} from "./contract.ts";

export function parsePublicationOperationRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "operation_id",
    "observation_id",
    "analysis_id",
    "expected_observation_revision",
    "expected_review_revision",
    "taxonomy_version_id",
    "initial_taxon_id",
    "note",
    "media_ids",
  ]);
  if (
    row.schema_version !== 1 ||
    (row.note !== null &&
      (typeof row.note !== "string" || [...row.note].length > 1000)) ||
    !Array.isArray(row.media_ids) || row.media_ids.length < 1 ||
    row.media_ids.length > 6
  ) {
    return invalidHistory();
  }
  const media = row.media_ids.map(historyUUID);
  if (new Set(media).size !== media.length) return invalidHistory();
  const request = {
    schema_version: 1 as const,
    operation_id: historyUUID(row.operation_id),
    observation_id: historyUUID(row.observation_id),
    analysis_id: historyUUID(row.analysis_id),
    expected_observation_revision: historyRevision(
      row.expected_observation_revision,
    ),
    expected_review_revision: historyRevision(row.expected_review_revision),
    taxonomy_version_id: historyUUID(row.taxonomy_version_id),
    initial_taxon_id: row.initial_taxon_id === null
      ? null
      : historyUUID(row.initial_taxon_id),
    note: row.note as string | null,
    media_ids: Object.freeze(media),
  };
  // PostgreSQL JSONB adds whitespace; reserve room within its 4KiB bound.
  if (new TextEncoder().encode(JSON.stringify(request)).length > 3800) {
    return invalidHistory();
  }
  return Object.freeze(request);
}
export type PublicationOperationRequest = ReturnType<
  typeof parsePublicationOperationRequest
>;
export function parsePublicationOperationReceipt(
  value: unknown,
  request: PublicationOperationRequest,
) {
  const row = exactObject(value, [
    "schema_version",
    "operation_id",
    "observation_id",
    "analysis_id",
    "status",
    "admitted_at",
  ]);
  if (
    row.schema_version !== 1 || row.status !== "accepted" ||
    row.operation_id !== request.operation_id ||
    row.observation_id !== request.observation_id ||
    row.analysis_id !== request.analysis_id ||
    typeof row.admitted_at !== "string" ||
    row.admitted_at.length > 40 || !Number.isFinite(Date.parse(row.admitted_at))
  ) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    operation_id: request.operation_id,
    observation_id: request.observation_id,
    analysis_id: request.analysis_id,
    status: "accepted" as const,
    admitted_at: row.admitted_at,
  });
}
