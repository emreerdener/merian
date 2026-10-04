import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

/** Exact-operation lookup only; the authenticated owner is never caller input. */
export function parsePublicationStatusRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "operation_id",
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: historyUUID(row.observation_id),
    operation_id: historyUUID(row.operation_id),
  });
}
export type PublicationStatusRequest = ReturnType<
  typeof parsePublicationStatusRequest
>;

export function parsePublicationStatusReceipt(
  value: unknown,
  request: PublicationStatusRequest,
) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "operation_id",
    "analysis_id",
    "status",
  ]);
  if (
    row.schema_version !== 1 || row.observation_id !== request.observation_id ||
    row.operation_id !== request.operation_id
  ) return invalidHistory();
  const status = row.status;
  if (
    status !== "accepted" && status !== "processing" &&
    status !== "photos_approved" &&
    status !== "needs_action" && status !== "admitted"
  ) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    operation_id: request.operation_id,
    observation_id: request.observation_id,
    analysis_id: historyUUID(row.analysis_id),
    status,
  });
}
