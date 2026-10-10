import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { preparedVideoCohortItems } from "./videoCohort.ts";
import {
  parseVideoSourceIdentity,
  parseVideoSourceReservationRequest,
} from "./videoSourceReservation.ts";

/** Prepared metadata contract, not an installed upload or execution authority. */
export const VIDEO_EVIDENCE_READER = 12;
export const VIDEO_EVIDENCE_REQUEST_MAX_BYTES = 4_096;
export const VIDEO_EVIDENCE_RECEIPT_MAX_BYTES = 8_192;
const identityKeys = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
  "analysis_id",
  "request_digest",
  "fingerprint_version",
  "fingerprint",
] as const;
const itemKeys = [
  "role",
  "index",
  "media_id",
  "content_type",
  "byte_count",
  "sha256",
] as const;

/** Bind all six/seven items to the original immutable candidate before any I/O. */
export async function buildVideoEvidenceUploadRequest(candidate: unknown) {
  const parsed = await parseVideoSourceReservationRequest(candidate);
  const input = parsed.input;
  const identity = parseVideoSourceIdentity({
    schema_version: 2,
    observation_id: input.observation_id,
    source_analysis_id: input.source_analysis_id,
    analysis_id: input.analysis_id,
    request_digest: input.request_digest,
    fingerprint_version: 1,
    fingerprint: parsed.fingerprint,
  });
  return Object.freeze({ ...identity, items: preparedVideoCohortItems(input) });
}
export type VideoEvidenceUploadRequest = Awaited<
  ReturnType<typeof buildVideoEvidenceUploadRequest>
>;

export async function decodeVideoEvidenceUploadRequest(
  bytes: Uint8Array,
  candidate: unknown,
) {
  const row = exactObject(json(bytes, VIDEO_EVIDENCE_REQUEST_MAX_BYTES), [
    ...identityKeys,
    "items",
  ]);
  const expected = await buildVideoEvidenceUploadRequest(candidate);
  matchIdentity(row, expected);
  matchItems(row.items, expected);
  return expected;
}

function matchIdentity(
  row: Record<string, unknown>,
  expected: VideoEvidenceUploadRequest,
) {
  if (identityKeys.some((key) => row[key] !== expected[key])) {
    return invalidHistory();
  }
}
function matchItems(value: unknown, expected: VideoEvidenceUploadRequest) {
  if (!Array.isArray(value) || value.length !== expected.items.length) {
    return invalidHistory();
  }
  return expected.items.map((item, index) => {
    const row = exactObject(value[index], itemKeys);
    if (itemKeys.some((key) => row[key] !== item[key])) return invalidHistory();
    return item;
  });
}
function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.startsWith("0000-") ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
  ) return invalidHistory();
  const time = Date.parse(value);
  if (!Number.isFinite(time) || new Date(time).toISOString() !== value) {
    return invalidHistory();
  }
  return value;
}
function receipt(
  value: unknown,
  expected: VideoEvidenceUploadRequest,
  owner: string,
) {
  const row = exactObject(value, [
    ...identityKeys,
    "owner_id",
    "state",
    "expires_at",
    "items",
  ]);
  matchIdentity(row, expected);
  if (
    row.owner_id !== owner ||
    (row.state !== "allocated" && row.state !== "ready")
  ) return invalidHistory();
  const expires = timestamp(row.expires_at);
  if (!Array.isArray(row.items) || row.items.length !== expected.items.length) {
    return invalidHistory();
  }
  const seen = new Set([
    owner,
    expected.observation_id,
    expected.source_analysis_id,
    expected.analysis_id,
    ...expected.items.map((item) => item.media_id),
  ]);
  const items = row.items.map((value, index) => {
    const item = exactObject(value, [...itemKeys, "object_id", "ready_at"]);
    const artifact = expected.items[index];
    if (itemKeys.some((key) => item[key] !== artifact[key])) {
      return invalidHistory();
    }
    const object = historyUUID(item.object_id);
    if (seen.has(object)) return invalidHistory();
    seen.add(object);
    const ready = item.ready_at === null ? null : timestamp(item.ready_at);
    if (ready !== null && ready >= expires) return invalidHistory();
    return Object.freeze({ ...artifact, object_id: object, ready_at: ready });
  });
  const state = items.every((item) => item.ready_at !== null)
    ? "ready"
    : "allocated";
  if (row.state !== state) return invalidHistory();
  return Object.freeze({
    ...expected,
    owner_id: owner,
    state,
    expires_at: expires,
    items: Object.freeze(items),
  });
}
export type VideoEvidenceReceipt = ReturnType<typeof receipt>;

/** Shape and association only. Caller must authenticate provenance and recheck SQL fences.
 * Prior bytes enforce immutable allocation/expiry and monotonic per-item completion.
 * Decoding an expired receipt permits recovery inspection, never renewed upload.
 */
export async function decodeVideoEvidenceReceipt(
  bytes: Uint8Array,
  candidate: unknown,
  ownerID: string,
  priorBytes?: Uint8Array,
): Promise<VideoEvidenceReceipt> {
  // Parse owned JSON snapshots before hashing can yield to caller mutations.
  const value = json(bytes, VIDEO_EVIDENCE_RECEIPT_MAX_BYTES);
  const prior = priorBytes === undefined
    ? undefined
    : json(priorBytes, VIDEO_EVIDENCE_RECEIPT_MAX_BYTES);
  const owner = historyUUID(ownerID);
  const expected = await buildVideoEvidenceUploadRequest(candidate);
  const current = receipt(value, expected, owner);
  if (prior !== undefined) {
    const previous = receipt(prior, expected, owner);
    if (
      current.expires_at !== previous.expires_at ||
      current.items.some((item, i) =>
        item.object_id !== previous.items[i].object_id ||
        (previous.items[i].ready_at !== null &&
          item.ready_at !== previous.items[i].ready_at)
      )
    ) return invalidHistory();
  }
  return current;
}
/** Fresh allocation is distinct from recovery/completion snapshots: no ready bytes yet. */
export async function decodeVideoEvidenceAllocation(
  bytes: Uint8Array,
  candidate: unknown,
  ownerID: string,
): Promise<VideoEvidenceReceipt> {
  const result = await decodeVideoEvidenceReceipt(bytes, candidate, ownerID);
  if (result.items.some((item) => item.ready_at !== null)) {
    return invalidHistory();
  }
  return result;
}
function json(bytes: Uint8Array, maximum: number): unknown {
  if (bytes.byteLength === 0 || bytes.byteLength > maximum) {
    return invalidHistory();
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
}
