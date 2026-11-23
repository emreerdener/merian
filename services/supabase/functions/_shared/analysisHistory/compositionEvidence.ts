import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import {
  COMPOSITION_ITEM_KEYS,
  compositionCohortItems,
} from "./compositionCohort.ts";
import { compositionRequestFingerprint } from "./compositionFingerprint.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

const identityKeys = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
  "analysis_id",
  "request_digest",
  "fingerprint_version",
  "fingerprint",
] as const;
export const COMPOSITION_RECEIPT_MAX_BYTES = 16_384;

/** Prepared immutable identity, separate from existing photo/audio/video wire
 * generations. Never treat this local projection as a server reservation.
 */
export async function compositionEvidenceIdentity(value: unknown) {
  const input = parseCompositionRequestStructure(value);
  const fingerprint = await compositionRequestFingerprint(input);
  return Object.freeze({
    schema_version: 3 as const,
    observation_id: input.observation_id,
    source_analysis_id: input.source_analysis_id,
    analysis_id: input.analysis_id,
    request_digest: input.request_digest,
    fingerprint_version: input.schema_version === 6 ? 2 as const : 1 as const,
    fingerprint,
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
function json(bytes: Uint8Array): unknown {
  if (
    !(bytes instanceof Uint8Array) || bytes.length === 0 ||
    bytes.length > COMPOSITION_RECEIPT_MAX_BYTES
  ) return invalidHistory();
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
}

/** Complete ordered association and monotonic allocation checks. Caller must
 * authenticate the response and recheck server account/deletion/expiry fences.
 * Expired receipts may be decoded for recovery; they never renew upload access.
 */
export async function decodeCompositionEvidenceReceipt(
  bytes: Uint8Array,
  value: unknown,
  ownerID: string,
  priorBytes?: Uint8Array,
) {
  const input = parseCompositionRequestStructure(value);
  const owner = historyUUID(ownerID);
  // Own both JSON snapshots before fingerprint hashing yields.
  const current = json(bytes),
    prior = priorBytes === undefined ? undefined : json(priorBytes);
  const expected = compositionCohortItems(input);
  const identity = await compositionEvidenceIdentity(input);
  function receipt(value: unknown) {
    const row = exactObject(value, [
      ...identityKeys,
      "owner_id",
      "state",
      "expires_at",
      "items",
    ]);
    if (
      identityKeys.some((key) => row[key] !== identity[key]) ||
      row.owner_id !== owner ||
      !Array.isArray(row.items) || row.items.length !== expected.length
    ) return invalidHistory();
    const expires = timestamp(row.expires_at);
    const seen = new Set([
      owner,
      identity.observation_id,
      identity.source_analysis_id,
      identity.analysis_id,
      ...expected.map((item) => item.media_id),
    ]);
    const items = row.items.map((value, index) => {
      const item = exactObject(value, [
        ...COMPOSITION_ITEM_KEYS,
        "object_id",
        "ready_at",
      ]);
      const artifact = expected[index];
      if (COMPOSITION_ITEM_KEYS.some((key) => item[key] !== artifact[key])) {
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
      ...identity,
      owner_id: owner,
      state,
      expires_at: expires,
      items: Object.freeze(items),
    });
  }
  const result = receipt(current);
  if (prior !== undefined) {
    const previous = receipt(prior);
    if (
      previous.expires_at !== result.expires_at ||
      result.items.some((item, index) =>
        item.object_id !== previous.items[index].object_id ||
        (previous.items[index].ready_at !== null &&
          item.ready_at !== previous.items[index].ready_at)
      )
    ) return invalidHistory();
  }
  return result;
}
export type CompositionEvidenceReceipt = Awaited<
  ReturnType<typeof decodeCompositionEvidenceReceipt>
>;
