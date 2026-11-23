import { parseCompositionRequestStructure } from "./compositionAdmission.ts";
import { compositionCohortItems } from "./compositionCohort.ts";
import { verifyCompositionEvidenceItem } from "./compositionVerification.ts";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import type { EvidenceReceipt } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { publicationAbortable } from "./publicationDeadline.ts";
import { decodeCompositionEvidenceReceipt } from "./compositionEvidence.ts";
import { createCompositionEvidenceRepository } from "./compositionEvidenceRepository.ts";
import {
  type CompositionSourceReservationRequest,
  parseCompositionSourceReservationRequest,
} from "./compositionSourceReservation.ts";

/** Trusted seam: RPC implementations must bound raw responses to 16384 bytes
 * before decoding, as createCompositionEvidenceRepository does. Never inject an
 * unbounded transport or pass request-controlled objects as RPC results.
 */
export interface CompositionUploadDependencies {
  reserve(
    owner: string,
    candidate: CompositionSourceReservationRequest,
    signal: AbortSignal,
  ): Promise<unknown>;
  write(
    receipt: EvidenceReceipt,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<void>;
  complete(
    owner: string,
    candidate: CompositionSourceReservationRequest,
    prior: Uint8Array,
    media: string,
    signal: AbortSignal,
  ): Promise<unknown>;
}
const json = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));

/** Trusted coordinator. The composition upload route supplies the authenticated owner. Never repairs/resamples bytes, retries or grants dispatch.
 */
export async function uploadCompositionEvidenceItem(
  candidate: unknown,
  owner: string,
  mediaID: string,
  bytes: Uint8Array,
  dependencies: CompositionUploadDependencies,
  caller: AbortSignal,
  now: () => number = Date.now,
) {
  const signal = AbortSignal.any([caller, AbortSignal.timeout(120_000)]);
  signal.throwIfAborted();
  const ownerID = historyUUID(owner), media = historyUUID(mediaID);
  const envelope = exactObject(candidate, [
    "schema_version",
    "input",
    "fingerprint_version",
    "fingerprint",
  ]);
  const input = parseCompositionRequestStructure(envelope.input);
  const item = compositionCohortItems(input).find((item) =>
    item.media_id === media
  );
  if (
    !item || !(bytes instanceof Uint8Array) ||
    bytes.byteLength !== item.byte_count
  ) return invalidHistory();
  const body = bytes.slice(); // Exact manifest bounds before copy, before any await.
  const original = await parseCompositionSourceReservationRequest({
    ...envelope,
    input,
  });
  signal.throwIfAborted();
  const verified = await verifyCompositionEvidenceItem(
    original.input,
    media,
    body,
  );
  signal.throwIfAborted();
  const allocation = await publicationAbortable(
    signal,
    () => dependencies.reserve(ownerID, original, signal),
  );
  signal.throwIfAborted();
  const receipt = await decodeCompositionEvidenceReceipt(
    json(allocation),
    original.input,
    ownerID,
  );
  signal.throwIfAborted();
  const allocated = receipt.items.find((item) => item.media_id === media)!;
  // Exact acknowledged replay is useful after expiry; never rewrite stored bytes.
  if (allocated.ready_at !== null) return receipt;
  const time = now();
  if (!Number.isFinite(time) || time >= Date.parse(receipt.expires_at)) {
    throw new HistoryError("analysis_history_evidence_unavailable");
  }
  const object = Object.freeze({
    owner_id: ownerID,
    observation_id: input.observation_id,
    analysis_id: input.analysis_id,
    media_id: media,
    object_id: allocated.object_id,
    content_type: allocated.content_type,
    byte_count: allocated.byte_count,
    sha256: allocated.sha256,
    expires_at: receipt.expires_at,
    ready_at: null,
  });
  await publicationAbortable(
    signal,
    () => dependencies.write(object, verified, signal),
  );
  signal.throwIfAborted();
  const prior = json(receipt);
  const answer = await publicationAbortable(
    signal,
    () => dependencies.complete(ownerID, original, prior, media, signal),
  );
  signal.throwIfAborted();
  const completed = await decodeCompositionEvidenceReceipt(
    json(answer),
    original.input,
    ownerID,
    prior,
  );
  signal.throwIfAborted();
  if (
    completed.items.find((item) => item.media_id === media)?.ready_at == null
  ) return invalidHistory();
  return completed;
}

/** Inert composition, sharing the existing private conditional-write/erasure namespace. */
export function createCompositionUploadDependencies(): CompositionUploadDependencies {
  const repository = createCompositionEvidenceRepository();
  const storage = new PrivateHistoryEvidenceStorage();
  return {
    ...repository,
    write: (receipt, bytes, signal) =>
      storage.writeOnce(receipt, bytes, signal),
  };
}
