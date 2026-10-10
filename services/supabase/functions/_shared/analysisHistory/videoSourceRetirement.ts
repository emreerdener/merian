import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import {
  parseVideoSourceIdentity,
  videoSourceIdentity,
} from "./videoSourceReservation.ts";

/** Prepared never-admitted V4 retirement only; no RPC or release consumer yet. */
export const VIDEO_SOURCE_RETIREMENT_READER = 12;
export const VIDEO_SOURCE_RETIREMENT_MAX_BYTES = 2_048;
const keys = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
  "analysis_id",
  "request_digest",
  "fingerprint_version",
  "fingerprint",
  "operation_id",
] as const;

/** Validate the closed wire identity, never the server's retirement eligibility. */
export function parseVideoSourceRetirementRequest(value: unknown) {
  const row = exactObject(value, keys);
  const { operation_id, ...scope } = row;
  const target = parseVideoSourceIdentity(scope);
  const operation = historyUUID(operation_id);
  if (
    [target.observation_id, target.source_analysis_id, target.analysis_id]
      .includes(operation)
  ) {
    return invalidHistory();
  }
  return Object.freeze({ ...target, operation_id: operation });
}
export type VideoSourceRetirementRequest = ReturnType<
  typeof parseVideoSourceRetirementRequest
>;
export type VideoSourceRetirementReceipt = VideoSourceRetirementRequest & {
  readonly owner_id: string;
  readonly state: "retired_pre_execution";
};
export function decodeVideoSourceRetirementRequest(bytes: Uint8Array) {
  return parseVideoSourceRetirementRequest(json(bytes));
}

/** Bind the frozen operation to the original complete candidate, not current selection. */
export async function buildVideoSourceRetirementRequest(
  candidate: unknown,
  operationID: string,
) {
  const operation = historyUUID(operationID);
  const target = await videoSourceIdentity(candidate);
  return parseVideoSourceRetirementRequest({
    ...target,
    operation_id: operation,
  });
}

/** A matching shape is not proof of server provenance and never authorizes local release. */
export async function decodeVideoSourceRetirementReceipt(
  bytes: Uint8Array,
  candidate: unknown,
  expected: VideoSourceRetirementRequest,
  ownerID: string,
): Promise<VideoSourceRetirementReceipt> {
  // Snapshot all mutable arguments before the candidate's fingerprint await.
  const request = parseVideoSourceRetirementRequest(expected);
  const owner = historyUUID(ownerID);
  const row = exactObject(json(bytes), [...keys, "owner_id", "state"]);
  if (
    row.owner_id !== owner || row.state !== "retired_pre_execution" ||
    keys.some((key) => row[key] !== request[key])
  ) {
    return invalidHistory();
  }
  const target = await videoSourceIdentity(candidate);
  if (
    Object.entries(target).some(([key, value]) =>
      request[key as keyof VideoSourceRetirementRequest] !== value
    )
  ) {
    return invalidHistory();
  }
  return Object.freeze({
    ...request,
    owner_id: owner,
    state: "retired_pre_execution",
  });
}
function json(bytes: Uint8Array): unknown {
  if (bytes.byteLength > VIDEO_SOURCE_RETIREMENT_MAX_BYTES) {
    return invalidHistory();
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
}
