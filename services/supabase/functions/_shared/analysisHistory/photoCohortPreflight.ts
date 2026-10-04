import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import {
  preparePublicationPhotoClassifier,
  type PublicationPhotoSource,
} from "./photoClassifier.ts";
import { validatePublicPhotoContainer } from "./publicPhotoContainer.ts";

/** A successful return means every ordered source passed preflight. It conveys
 * no moderation approval: invocation still requires durable proof and dispatch.
 * No quota admission may happen until this whole function succeeds. */
export async function preparePublicationPhotoCohort(
  inputs: readonly PublicationPhotoSource[],
  dependencies: {
    readSource?: (
      source: Readonly<PublicationPhotoSource>,
      signal: AbortSignal,
    ) => Promise<Uint8Array>;
    apiKey?: () => string | undefined;
    fetcher?: typeof fetch;
    signal?: AbortSignal;
  } = {},
) {
  if (!Array.isArray(inputs) || inputs.length < 1 || inputs.length > 6) {
    invalidHistory();
  }
  // Snapshot and validate the entire cohort before the first asynchronous read.
  const sources = inputs.map((input) => {
    const s = { ...input };
    exactObject(s, [
      "media_id",
      "object_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    historyUUID(s.media_id);
    historyUUID(s.object_id);
    if (
      s.media_id === s.object_id ||
      !["image/jpeg", "image/png"].includes(s.content_type) ||
      !Number.isSafeInteger(s.byte_count) || s.byte_count < 1 ||
      s.byte_count > 12 * 1024 * 1024 ||
      typeof s.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(s.sha256)
    ) invalidHistory();
    return Object.freeze(s);
  });
  if (
    new Set(sources.map((s) => s.media_id)).size !== sources.length ||
    new Set(sources.map((s) => s.object_id)).size !== sources.length ||
    sources.reduce((sum, s) => sum + s.byte_count, 0) > 32 * 1024 * 1024
  ) invalidHistory();
  const timeout = AbortSignal.timeout(60_000);
  const signal = dependencies.signal
    ? AbortSignal.any([timeout, dependencies.signal])
    : timeout;
  const storage = new PrivateHistoryEvidenceStorage();
  const verified = new Map<string, Uint8Array>();
  try {
    for (const source of sources) {
      signal.throwIfAborted();
      const bytes = (await (dependencies.readSource ?? ((s, signal) =>
        storage.readVerified(s, signal)))(source, signal)).slice();
      signal.throwIfAborted();
      if (
        bytes.length !== source.byte_count ||
        await evidenceDigest(bytes) !== source.sha256
      ) {
        invalidHistory();
      }
      validatePublicPhotoContainer(bytes, source.content_type);
      signal.throwIfAborted();
      verified.set(source.media_id, bytes);
    }
  } catch {
    verified.clear();
    throw new HistoryError("analysis_history_evidence_unavailable");
  }
  let selected = false;
  return Object.freeze({
    sources: Object.freeze(sources),
    // One provider attempt per orchestration pass. Hold at most 32 MiB raw;
    // release all unselected buffers BEFORE the classifier builds one base64
    // request. Never retain a cohort of eagerly serialized provider bodies.
    prepare: async (media: string) => {
      if (selected) {
        throw new HistoryError("analysis_history_operation_conflict");
      }
      const source = sources.find((s) => s.media_id === media),
        bytes = verified.get(media);
      if (!source || !bytes) return invalidHistory();
      selected = true;
      verified.clear();
      signal.throwIfAborted();
      const prepared = await preparePublicationPhotoClassifier(source, {
        readSource: () => Promise.resolve(bytes),
        apiKey: dependencies.apiKey,
        fetcher: dependencies.fetcher,
      });
      // CPU-bound digest/container/serialization phases check cancellation at
      // their boundaries; this is not preemptive execution interruption.
      signal.throwIfAborted();
      return prepared;
    },
  });
}
