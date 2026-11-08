import {
  exactObject,
  historyRevision,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";

/** A read for one explicit analysis; no operation or consent is created. */
export function parsePublicationConsentRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: historyUUID(row.observation_id),
    analysis_id: historyUUID(row.analysis_id),
  });
}
export type PublicationConsentRequest = ReturnType<
  typeof parsePublicationConsentRequest
>;

/** Descriptive candidates only. Admission revalidates exact selected receipts. */
export function parsePublicationConsentSnapshot(
  value: unknown,
  request: PublicationConsentRequest,
) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "expected_observation_revision",
    "expected_review_revision",
    "taxonomy_version_id",
    "initial_taxon_id",
    "media",
  ]);
  if (
    row.schema_version !== 1 || row.observation_id !== request.observation_id ||
    row.analysis_id !== request.analysis_id || row.initial_taxon_id !== null ||
    !Array.isArray(row.media) || row.media.length < 1 || row.media.length > 64
  ) return invalidHistory();
  // Reuse the immutable V2 count, MIME, digest, identity and total-byte bounds.
  const manifest = parseProtectedEvidenceManifest({
    schema_version: 2,
    items: row.media.map((value) => {
      const photo = exactObject(value, [
        "media_id",
        "content_type",
        "byte_count",
        "sha256",
      ]);
      return { kind: "image", ...photo };
    }),
  });
  const media = manifest.items.map((item) => {
    if (item.kind !== "image") return invalidHistory();
    const { kind: _kind, ...photo } = item;
    return Object.freeze(photo);
  });
  return Object.freeze({
    ...request,
    expected_observation_revision: historyRevision(
      row.expected_observation_revision,
    ),
    expected_review_revision: historyRevision(row.expected_review_revision),
    taxonomy_version_id: historyUUID(row.taxonomy_version_id),
    initial_taxon_id: null,
    media: Object.freeze(media),
  });
}
