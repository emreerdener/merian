import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { videoSourceFingerprint } from "./videoSourceFingerprint.ts";

/** Prepared V4 lifecycle contract only. No installed RPC, route or queue consumer. */
export const VIDEO_SOURCE_READER = 12;
export const VIDEO_SOURCE_MAX_REQUEST_BYTES = 1_048_576;
export const VIDEO_SOURCE_MAX_RECEIPT_BYTES = 2_048;
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
export type VideoSourceHold = typeof holdReasons[number];

/** Copy and freeze the complete graph before hashing; preserve the replay digest. */
export async function parseVideoSourceReservationRequest(value: unknown) {
  const row = exactObject(value, envelopeKeys);
  if (row.schema_version !== 2 || row.fingerprint_version !== 1) {
    return invalidHistory();
  }
  const fingerprint = digest(row.fingerprint);
  const input = parsePreparedVideoAdmission(row.input);
  freeze(input);
  if (await videoSourceFingerprint(input) !== fingerprint) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 2 as const,
    input,
    fingerprint_version: 1 as const,
    fingerprint,
  });
}
export type VideoSourceReservationRequest = Awaited<
  ReturnType<typeof parseVideoSourceReservationRequest>
>;
export function decodeVideoSourceReservationRequest(bytes: Uint8Array) {
  return parseVideoSourceReservationRequest(
    json(bytes, VIDEO_SOURCE_MAX_REQUEST_BYTES),
  );
}
function identity(value: unknown) {
  const row = exactObject(value, identityKeys);
  if (row.schema_version !== 2 || row.fingerprint_version !== 1) {
    return invalidHistory();
  }
  const observation = historyUUID(row.observation_id),
    source = historyUUID(row.source_analysis_id),
    analysis = historyUUID(row.analysis_id);
  if (new Set([observation, source, analysis]).size !== 3) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: 2 as const,
    observation_id: observation,
    source_analysis_id: source,
    analysis_id: analysis,
    request_digest: digest(row.request_digest),
    fingerprint_version: 1 as const,
    fingerprint: digest(row.fingerprint),
  });
}
export type VideoSourceIdentity = ReturnType<typeof identity>;
export async function videoSourceIdentity(
  candidate: unknown,
): Promise<VideoSourceIdentity> {
  const request = await parseVideoSourceReservationRequest(candidate);
  return identity({
    schema_version: 2,
    observation_id: request.input.observation_id,
    source_analysis_id: request.input.source_analysis_id,
    analysis_id: request.input.analysis_id,
    request_digest: request.input.request_digest,
    fingerprint_version: 1,
    fingerprint: request.fingerprint,
  });
}

/** Read-only lookup of this exact candidate; absence never authorizes replacement. */
export const buildVideoSourceRecoveryRequest = videoSourceIdentity;
export function decodeVideoSourceRecoveryRequest(
  bytes: Uint8Array,
): VideoSourceIdentity {
  return identity(json(bytes, VIDEO_SOURCE_MAX_RECEIPT_BYTES));
}

export type VideoSourceReservationReceipt =
  & VideoSourceIdentity
  & { readonly owner_id: string }
  & (
    | { readonly state: "reserved" }
    | { readonly state: "held"; readonly reason: VideoSourceHold }
    | { readonly state: "unavailable" }
  );

function scoped(
  row: Record<string, unknown>,
  target: VideoSourceIdentity,
  owner: string,
) {
  if (
    row.owner_id !== historyUUID(owner) ||
    identityKeys.some((key) => row[key] !== target[key])
  ) return invalidHistory();
}
function ordinary(
  row: Record<string, unknown>,
  target: VideoSourceIdentity,
  owner: string,
): VideoSourceReservationReceipt {
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
  const value = json(bytes, VIDEO_SOURCE_MAX_RECEIPT_BYTES);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  return value as Record<string, unknown>;
}
/** Reserved reports binding/occupancy only. It permits no upload or provider call. */
export async function decodeVideoSourceReservationReceipt(
  bytes: Uint8Array,
  candidate: unknown,
  owner: string,
): Promise<VideoSourceReservationReceipt> {
  const row = record(bytes);
  const target = await videoSourceIdentity(candidate);
  return ordinary(row, target, owner);
}
/** Lookup observations use the same closed states; none grants absence or release proof. */
export const decodeVideoSourceRecoveryReceipt =
  decodeVideoSourceReservationReceipt;

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
