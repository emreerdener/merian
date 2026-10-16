import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { parsePublicationStatusReceipt } from "./publicationStatus.ts";

/** Observation-wide recovery; ownership always comes from authenticated context. */
export function parsePublicationTargetRequest(value: unknown) {
  const row = exactObject(value, ["schema_version", "observation_id"]);
  if (row.schema_version !== 1) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: historyUUID(row.observation_id),
  });
}
export type PublicationTargetRequest = ReturnType<
  typeof parsePublicationTargetRequest
>;

/** A non-null database envelope distinguishes vacancy from empty SDK replies. */
export function parsePublicationTargetEnvelope(
  value: unknown,
  request: PublicationTargetRequest,
) {
  const envelope = exactObject(value, ["schema_version", "operation"]);
  if (envelope.schema_version !== 1) return invalidHistory();
  if (envelope.operation === null) return null;
  const row = exactObject(envelope.operation, [
    "schema_version",
    "observation_id",
    "operation_id",
    "analysis_id",
    "status",
  ]);
  return parsePublicationStatusReceipt(row, {
    schema_version: 1,
    observation_id: request.observation_id,
    operation_id: historyUUID(row.operation_id),
  });
}
