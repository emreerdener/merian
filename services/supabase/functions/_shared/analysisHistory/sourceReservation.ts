import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { sourceReservationFingerprint } from "./sourceFingerprint.ts";

/** Prepared contract only. No RPC, reservation writer, or execution capability. */
export const SOURCE_RESERVATION_READER = 11;
export const SOURCE_RESERVATION_MAX_REQUEST_BYTES = 1_048_576;
export const SOURCE_RESERVATION_MAX_RECEIPT_BYTES = 2_048;

export interface SourceReservationRequest {
  readonly schema_version: 1;
  readonly input: Readonly<Record<string, unknown>>;
  readonly fingerprint_version: 1;
  readonly fingerprint: string;
}

const identityKeys = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
  "analysis_id",
  "request_digest",
  "fingerprint_version",
  "fingerprint",
] as const;

/** Snapshot before hashing: callers cannot alter the accepted input across await. */
export async function parseSourceReservationRequest(
  value: unknown,
): Promise<SourceReservationRequest> {
  const row = exactObject(value, [
    "schema_version",
    "input",
    "fingerprint_version",
    "fingerprint",
  ]);
  if (row.schema_version !== 1 || row.fingerprint_version !== 1) {
    return invalidHistory();
  }
  const fingerprint = digest(row.fingerprint);
  const input = parseExecutableAnalysisInput(row.input);
  if (input.schema_version !== 2 && input.schema_version !== 3) {
    return invalidHistory();
  }
  freeze(input);
  if (await sourceReservationFingerprint(input) !== fingerprint) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 1,
    input,
    fingerprint_version: 1,
    fingerprint,
  });
}

export function decodeSourceReservationRequest(bytes: Uint8Array) {
  return parseSourceReservationRequest(
    json(bytes, SOURCE_RESERVATION_MAX_REQUEST_BYTES),
  );
}

function parseSourceReservationIdentity(value: unknown) {
  const row = exactObject(value, identityKeys);
  if (row.schema_version !== 1 || row.fingerprint_version !== 1) {
    return invalidHistory();
  }
  const observation = historyUUID(row.observation_id);
  const source = historyUUID(row.source_analysis_id);
  const analysis = historyUUID(row.analysis_id);
  if (new Set([observation, source, analysis]).size !== 3) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: observation,
    source_analysis_id: source,
    analysis_id: analysis,
    request_digest: digest(row.request_digest),
    fingerprint_version: 1 as const,
    fingerprint: digest(row.fingerprint),
  });
}
export type SourceReservationIdentity = ReturnType<
  typeof parseSourceReservationIdentity
>;

/** Scope from a validated immutable request, never from a response or current selection. */
export async function sourceReservationIdentity(
  value: unknown,
): Promise<SourceReservationIdentity> {
  const request = await parseSourceReservationRequest(value);
  return parseSourceReservationIdentity({
    schema_version: 1,
    observation_id: request.input.observation_id,
    source_analysis_id: request.input.source_analysis_id,
    analysis_id: request.input.analysis_id,
    request_digest: request.input.request_digest,
    fingerprint_version: 1,
    fingerprint: request.fingerprint,
  });
}

export type SourceReservationHold =
  | "source_occupied"
  | "ambiguous_occupancy"
  | "coverage_incomplete"
  | "malformed_linkage"
  | "terminal_unproven";
interface SourceScope {
  readonly schema_version: 1;
  readonly owner_id: string;
  readonly observation_id: string;
  readonly source_analysis_id: string;
}
export type SourceReservationReceipt =
  & SourceScope
  & (
    | (SourceReservationIdentity & { readonly state: "reserved" })
    | { readonly state: "held"; readonly reason: SourceReservationHold }
    | { readonly state: "unavailable" }
  );
const scopeKeys = [
  "schema_version",
  "owner_id",
  "observation_id",
  "source_analysis_id",
  "state",
] as const;

/** Reserved acknowledges an immutable binding, not current admission/execution phase. */
export async function decodeSourceReservationReceipt(
  bytes: Uint8Array,
  expected: unknown,
  ownerID: string,
): Promise<SourceReservationReceipt> {
  const value = json(bytes, SOURCE_RESERVATION_MAX_RECEIPT_BYTES);
  const target = await sourceReservationIdentity(expected);
  const row = scoped(value, target, ownerID);
  const scope = {
    schema_version: 1 as const,
    owner_id: ownerID,
    observation_id: target.observation_id,
    source_analysis_id: target.source_analysis_id,
  };
  if (row.state === "reserved") {
    exactObject(row, [...identityKeys, "owner_id", "state"]);
    if (Object.entries(target).some(([key, item]) => row[key] !== item)) {
      return invalidHistory();
    }
    return Object.freeze({ ...target, ...scope, state: "reserved" });
  }
  if (row.state === "unavailable") {
    exactObject(row, scopeKeys);
    return Object.freeze({ ...scope, state: "unavailable" });
  }
  exactObject(row, [...scopeKeys, "reason"]);
  if (row.state !== "held") return invalidHistory();
  return Object.freeze({
    ...scope,
    state: "held",
    reason: holdReason(row.reason),
  });
}
function holdReason(value: unknown): SourceReservationHold {
  switch (value) {
    case "source_occupied":
    case "ambiguous_occupancy":
    case "coverage_incomplete":
    case "malformed_linkage":
    case "terminal_unproven":
      return value;
    default:
      return invalidHistory();
  }
}

/** A separate explicit action retires a never-admitted reservation, not funded execution. */
export function parseSourceRetirementRequest(value: unknown) {
  const row = exactObject(value, [...identityKeys, "operation_id"]);
  const { operation_id, ...identity } = row;
  const request = parseSourceReservationIdentity(identity);
  const operation = historyUUID(operation_id);
  if (
    [request.observation_id, request.source_analysis_id, request.analysis_id]
      .includes(operation)
  ) return invalidHistory();
  return Object.freeze({ ...request, operation_id: operation });
}
export type SourceRetirementRequest = ReturnType<
  typeof parseSourceRetirementRequest
>;

export function decodeSourceRetirementRequest(
  bytes: Uint8Array,
): SourceRetirementRequest {
  return parseSourceRetirementRequest(
    json(bytes, SOURCE_RESERVATION_MAX_RECEIPT_BYTES),
  );
}

/** Build from the original full candidate, never a caller-synthesized digest tuple. */
export async function buildSourceRetirementRequest(
  candidate: unknown,
  operationID: string,
): Promise<SourceRetirementRequest> {
  const identity = await sourceReservationIdentity(candidate);
  return parseSourceRetirementRequest({
    ...identity,
    operation_id: operationID,
  });
}

export async function decodeSourceRetirementReceipt(
  bytes: Uint8Array,
  candidate: unknown,
  expected: SourceRetirementRequest,
  ownerID: string,
) {
  const request = parseSourceRetirementRequest(expected);
  const value = json(bytes, SOURCE_RESERVATION_MAX_RECEIPT_BYTES);
  const identity = await sourceReservationIdentity(candidate);
  if (
    identityKeys.some((key) => request[key] !== identity[key])
  ) return invalidHistory();
  const row = scoped(value, identity, ownerID);
  exactObject(row, [...identityKeys, "operation_id", "owner_id", "state"]);
  if (
    Object.entries(request).some(([key, item]) => row[key] !== item) ||
    row.state !== "retired_unfunded"
  ) return invalidHistory();
  return Object.freeze({
    ...request,
    owner_id: ownerID,
    state: "retired_unfunded" as const,
  });
}

function scoped(
  value: unknown,
  expected: SourceReservationIdentity,
  ownerID: string,
) {
  const target = parseSourceReservationIdentity(expected);
  const owner = historyUUID(ownerID);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const row = value as Record<string, unknown>;
  if (
    row.owner_id !== owner ||
    row.schema_version !== 1 || row.observation_id !== target.observation_id ||
    row.source_analysis_id !== target.source_analysis_id
  ) return invalidHistory();
  return row;
}
function digest(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
    return invalidHistory();
  }
  return value;
}
function json(bytes: Uint8Array, limit: number): unknown {
  if (bytes.byteLength > limit) return invalidHistory();
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
}
function freeze(value: unknown): void {
  if (value !== null && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
}
