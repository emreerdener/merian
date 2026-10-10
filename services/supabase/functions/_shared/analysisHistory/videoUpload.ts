import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import type { EvidenceReceipt } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { publicationAbortable } from "./publicationDeadline.ts";
import { verifyPreparedVideoSource } from "./retainedVideoContainer.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { verifyPreparedVideoAudio } from "./videoAudioContainer.ts";
import { preparedVideoCohortItems } from "./videoCohort.ts";
import { decodeVideoEvidenceReceipt } from "./videoEvidence.ts";
import { createVideoEvidenceRepository } from "./videoEvidenceRepository.ts";
import { verifyPreparedVideoFrame } from "./videoFrameContainer.ts";
import {
  parseVideoSourceReservationRequest,
  type VideoSourceReservationRequest,
} from "./videoSourceReservation.ts";

/** Trusted seam: RPC implementations must bound raw responses to 8192 bytes
 * before decoding, as createVideoEvidenceRepository does. Never inject an
 * unbounded transport or pass request-controlled objects as RPC results.
 */
export interface VideoUploadDependencies {
  reserve(
    owner: string,
    candidate: VideoSourceReservationRequest,
    signal: AbortSignal,
  ): Promise<unknown>;
  write(
    receipt: EvidenceReceipt,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<void>;
  complete(
    owner: string,
    candidate: VideoSourceReservationRequest,
    prior: Uint8Array,
    media: string,
    signal: AbortSignal,
  ): Promise<unknown>;
}
const json = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));

/** Prepared trusted coordinator. Caller supplies authenticated owner; no HTTP
 * route installs this. Never repairs/resamples bytes, retries or grants dispatch.
 */
export async function uploadVideoEvidenceItem(
  candidate: unknown,
  owner: string,
  mediaID: string,
  bytes: Uint8Array,
  dependencies: VideoUploadDependencies,
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
  const input = parsePreparedVideoAdmission(envelope.input);
  const item = preparedVideoCohortItems(input).find((item) =>
    item.media_id === media
  );
  if (
    !item || !(bytes instanceof Uint8Array) ||
    bytes.byteLength !== item.byte_count
  ) return invalidHistory();
  const body = bytes.slice(); // Exact manifest bounds before copy, before any await.
  const original = await parseVideoSourceReservationRequest({
    ...envelope,
    input,
  });
  signal.throwIfAborted();
  const args = [
    input.evidence_manifest,
    input.observation_id,
    input.analysis_id,
  ] as const;
  const verified = item.role === "source"
    ? await verifyPreparedVideoSource(...args, body)
    : item.role === "frame"
    ? await verifyPreparedVideoFrame(...args, item.index!, body)
    : await verifyPreparedVideoAudio(...args, body);
  signal.throwIfAborted();
  const allocation = await publicationAbortable(
    signal,
    () => dependencies.reserve(ownerID, original, signal),
  );
  signal.throwIfAborted();
  const receipt = await decodeVideoEvidenceReceipt(
    json(allocation),
    original,
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
  const completed = await decodeVideoEvidenceReceipt(
    json(answer),
    original,
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
export function createVideoUploadDependencies(): VideoUploadDependencies {
  const repository = createVideoEvidenceRepository();
  const storage = new PrivateHistoryEvidenceStorage();
  return {
    ...repository,
    write: (receipt, bytes, signal) =>
      storage.writeOnce(receipt, bytes, signal),
  };
}
