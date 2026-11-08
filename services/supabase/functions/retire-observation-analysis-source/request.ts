import {
  exactObject,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  buildSourceRetirementRequest,
  parseSourceReservationRequest,
  SOURCE_RESERVATION_MAX_REQUEST_BYTES,
} from "../_shared/analysisHistory/sourceReservation.ts";

// Minimal schema-1 envelope adds 87 UTF-8 bytes around the original candidate.
export const SOURCE_RETIREMENT_HTTP_MAX_BYTES =
  SOURCE_RESERVATION_MAX_REQUEST_BYTES + 87;

/** Public full-candidate envelope, deliberately distinct from the frozen SQL tuple. */
export async function parseSourceRetirementEnvelope(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "candidate",
    "operation_id",
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  // Capture operation before hashing awaits; caller mutation cannot replace it.
  const operation = historyUUID(row.operation_id);
  const candidate = await parseSourceReservationRequest(row.candidate);
  await buildSourceRetirementRequest(candidate, operation);
  return Object.freeze({
    schema_version: 1 as const,
    candidate,
    operation_id: operation,
  });
}
