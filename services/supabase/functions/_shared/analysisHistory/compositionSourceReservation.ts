import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import { compositionRequestFingerprint } from "./compositionFingerprint.ts";

/** Schema-3 reservation envelope for the default-closed metadata SQL lane.
 * The public reservation route supports this lane; mixed execution remains closed. */
export const COMPOSITION_SOURCE_READER_VERSION = 14;
/** Identity has already passed the closed pair check, or is a recovery shape
 * that SQL must compare against the durably stored full input. */
export function compositionSourceReaderVersion(
  identity: { fingerprint_version: 1 | 2 },
): 14 | 15 {
  return identity.fingerprint_version === 2 ? 15 : 14;
}
export const COMPOSITION_SOURCE_MAX_REQUEST_BYTES = 1_048_576;
export const COMPOSITION_SOURCE_MAX_RECEIPT_BYTES = 2_048;
const identityKeys = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
  "analysis_id",
  "request_digest",
  "fingerprint_version",
  "fingerprint",
] as const;
const envelopeKeys = [
  "schema_version",
  "input",
  "fingerprint_version",
  "fingerprint",
] as const;
const holdReasons = [
  "source_occupied",
  "ambiguous_occupancy",
  "coverage_incomplete",
  "malformed_linkage",
  "terminal_unproven",
] as const;
export type CompositionSourceHold = typeof holdReasons[number];

/** Copy and freeze the complete graph before hashing; preserve the replay digest. */
export async function parseCompositionSourceReservationRequest(value: unknown) {
  const row = exactObject(value, envelopeKeys);
  if (
    row.schema_version !== 3 ||
    (row.fingerprint_version !== 1 && row.fingerprint_version !== 2)
  ) {
    return invalidHistory();
  }
  const fingerprint = digest(row.fingerprint);
  const input = parseCompositionRequestStructure(row.input);
  if (row.fingerprint_version !== (input.schema_version === 6 ? 2 : 1)) {
    return invalidHistory();
  }
  freeze(input);
  if (await compositionRequestFingerprint(input) !== fingerprint) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 3 as const,
    input,
    fingerprint_version: row.fingerprint_version,
    fingerprint,
  });
}
export type CompositionSourceReservationRequest = Awaited<
  ReturnType<typeof parseCompositionSourceReservationRequest>
>;
export function decodeCompositionSourceReservationRequest(bytes: Uint8Array) {
  return parseCompositionSourceReservationRequest(
    json(bytes, COMPOSITION_SOURCE_MAX_REQUEST_BYTES),
  );
}
/** Shape validation only; this identity grants no ownership or release authority. */
export function parseCompositionSourceIdentity(value: unknown) {
  const row = exactObject(value, identityKeys);
  if (
    row.schema_version !== 3 ||
    (row.fingerprint_version !== 1 && row.fingerprint_version !== 2)
  ) {
    return invalidHistory();
  }
  const observation = historyUUID(row.observation_id),
    source = historyUUID(row.source_analysis_id),
    analysis = historyUUID(row.analysis_id);
  if (new Set([observation, source, analysis]).size !== 3) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 3 as const,
    observation_id: observation,
    source_analysis_id: source,
    analysis_id: analysis,
    request_digest: digest(row.request_digest),
    fingerprint_version: row.fingerprint_version,
    fingerprint: digest(row.fingerprint),
  });
}
export type CompositionSourceIdentity = ReturnType<
  typeof parseCompositionSourceIdentity
>;
export async function compositionSourceIdentity(
  candidate: unknown,
): Promise<CompositionSourceIdentity> {
  const request = await parseCompositionSourceReservationRequest(candidate);
  return parseCompositionSourceIdentity({
    schema_version: 3,
    observation_id: request.input.observation_id,
    source_analysis_id: request.input.source_analysis_id,
    analysis_id: request.input.analysis_id,
    request_digest: request.input.request_digest,
    fingerprint_version: request.fingerprint_version,
    fingerprint: request.fingerprint,
  });
}

/** Read-only lookup of this exact candidate; absence never authorizes replacement. */
export const buildCompositionSourceRecoveryRequest = compositionSourceIdentity;
export function decodeCompositionSourceRecoveryRequest(
  bytes: Uint8Array,
): CompositionSourceIdentity {
  return parseCompositionSourceIdentity(
    json(bytes, COMPOSITION_SOURCE_MAX_RECEIPT_BYTES),
  );
}

export type CompositionSourceReservationReceipt =
  & CompositionSourceIdentity
  & { readonly owner_id: string }
  & (
    | { readonly state: "reserved" }
    | { readonly state: "held"; readonly reason: CompositionSourceHold }
    | { readonly state: "unavailable" }
  );

function scoped(
  row: Record<string, unknown>,
  target: CompositionSourceIdentity,
  owner: string,
) {
  if (
    row.owner_id !== historyUUID(owner) ||
    identityKeys.some((key) => row[key] !== target[key])
  ) return invalidHistory();
}
function ordinary(
  row: Record<string, unknown>,
  target: CompositionSourceIdentity,
  owner: string,
): CompositionSourceReservationReceipt {
  const keys = [...identityKeys, "owner_id", "state"];
  scoped(row, target, owner);
  if (row.state === "reserved" || row.state === "unavailable") {
    exactObject(row, keys);
    return Object.freeze({ ...target, owner_id: owner, state: row.state });
  }
  exactObject(row, [...keys, "reason"]);
  const reason = holdReasons.find((value) => value === row.reason);
  if (row.state !== "held" || !reason) return invalidHistory();
  return Object.freeze({ ...target, owner_id: owner, state: "held", reason });
}
function record(bytes: Uint8Array): Record<string, unknown> {
  const value = json(bytes, COMPOSITION_SOURCE_MAX_RECEIPT_BYTES);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  return value as Record<string, unknown>;
}
/** Reserved reports binding/occupancy only. It permits no upload or provider call. */
export async function decodeCompositionSourceReservationReceipt(
  bytes: Uint8Array,
  candidate: unknown,
  owner: string,
): Promise<CompositionSourceReservationReceipt> {
  const row = record(bytes);
  const target = await compositionSourceIdentity(candidate);
  return ordinary(row, target, owner);
}
/** Lookup observations use the same closed states; none grants absence or release proof. */
export const decodeCompositionSourceRecoveryReceipt =
  decodeCompositionSourceReservationReceipt;

function digest(value: unknown): string {
  if (
    typeof value !== "string" || value.length !== 64 ||
    !/^[0-9a-f]{64}$/.test(value)
  ) return invalidHistory();
  return value;
}
function json(bytes: Uint8Array, maximum: number): unknown {
  if (bytes.byteLength > maximum) return invalidHistory();
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
}
function freeze(value: unknown): void {
  if (value !== null && typeof value === "object") {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
}
