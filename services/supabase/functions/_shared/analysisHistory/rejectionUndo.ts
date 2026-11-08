import {
  exactObject,
  historyRevision,
  historyUUID,
  invalidHistory,
} from "./contract.ts";

const keys = [
  "schema_version",
  "observation_id",
  "analysis_id",
  "expected_observation_revision",
  "expected_review_revision",
] as const;
export function parseRejectionUndoLookup(value: unknown) {
  const row = exactObject(value, keys);
  if (row.schema_version !== 1) return invalidHistory();
  const observation = historyRevision(row.expected_observation_revision);
  const review = historyRevision(row.expected_review_revision);
  if (observation >= 2147483647 || review >= 2147483647) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: historyUUID(row.observation_id),
    analysis_id: historyUUID(row.analysis_id),
    expected_observation_revision: observation,
    expected_review_revision: review,
  });
}
export function parseRejectionUndoEligibility(
  value: unknown,
  expected: ReturnType<typeof parseRejectionUndoLookup>,
) {
  const status = (value as { status?: unknown } | null)?.status;
  if (status !== "available" && status !== "unavailable") {
    return invalidHistory();
  }
  const row = exactObject(value, [
    ...keys,
    "status",
    ...(status === "available" ? ["rejection_operation_id"] : ["reason"]),
  ]);
  const request = parseRejectionUndoLookup(
    Object.fromEntries(keys.map((key) => [key, row[key]])),
  );
  if (
    JSON.stringify(request) !==
      JSON.stringify(parseRejectionUndoLookup(expected))
  ) return invalidHistory();
  if (status === "available") {
    return Object.freeze({
      ...request,
      status,
      rejection_operation_id: historyUUID(row.rejection_operation_id),
    });
  }
  const reason = row.reason;
  if (
    ![
      "community_authority",
      "not_rejected",
      "receipt_unavailable",
      "rejection_changed",
      "revision_conflict",
    ].includes(reason as string)
  ) return invalidHistory();
  return Object.freeze({ ...request, status, reason });
}
