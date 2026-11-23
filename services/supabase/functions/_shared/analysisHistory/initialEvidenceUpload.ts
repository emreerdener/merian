import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import {
  initialEvidenceArtifacts,
  parseInitialEvidenceManifest,
} from "./initialEvidenceManifest.ts";
import { createInitialEvidenceRepository } from "./initialEvidenceRepository.ts";
import {
  type InitialRetentionRepository,
  initialRetentionRequest,
  type InitialRetentionStorage,
  parseInitialRetentionReceipt,
} from "./initialEvidenceRetention.ts";

export interface InitialEvidenceUploadDependencies {
  repository: InitialRetentionRepository;
  storage: Pick<InitialRetentionStorage, "writeOnce"> & {
    verifyStored(
      receipt: Parameters<InitialRetentionStorage["writeOnce"]>[0],
      signal: AbortSignal,
    ): Promise<void>;
  };
}

/** One artifact of an already admitted ordinary ingestion job. The SQL owner
 * binds the complete request before issuing any private object identifier.
 * This neither admits a job nor dispatches inference, changes funding, seals a
 * result or authorizes a client to release originals. Missing job stays closed.
 */
export async function uploadInitialEvidenceArtifact(
  owner: string,
  candidate: unknown,
  mediaID: string,
  input: Uint8Array,
  dependencies: InitialEvidenceUploadDependencies,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const ownerID = historyUUID(owner), media = historyUUID(mediaID);
  const row = exactObject(candidate, [
    "schema_version",
    "scan_id",
    "generation",
    "evidence_digest",
    "evidence_manifest",
  ]);
  const scan = historyUUID(row.scan_id),
    generation = historyUUID(row.generation);
  // Own the closed graph and bound the role before copying any request bytes.
  const manifest = parseInitialEvidenceManifest(
    row.evidence_manifest,
    scan,
    generation,
  );
  const artifacts = initialEvidenceArtifacts(manifest);
  const item = artifacts.find((value) => value.media_id === media);
  if (
    !item || !(input instanceof Uint8Array) ||
    input.byteLength !== item.byte_count ||
    [scan, generation, ...artifacts.map((value) => value.media_id)].includes(
      ownerID,
    )
  ) return invalidHistory();
  const bytes = input.slice();
  const request = await initialRetentionRequest({
    ...row,
    evidence_manifest: manifest,
  });
  signal.throwIfAborted();
  if (await evidenceDigest(bytes) !== item.sha256) return invalidHistory();
  signal.throwIfAborted();
  let receipt = parseInitialRetentionReceipt(
    await dependencies.repository.reserve(ownerID, request, signal),
    ownerID,
    request,
  );
  signal.throwIfAborted();
  const allocated = receipt.items.find((value) => value.media_id === media)!;
  if (!allocated.ready) {
    await dependencies.storage.writeOnce(allocated, bytes, signal);
    signal.throwIfAborted();
  }
  // Even an acknowledged replay must prove the object is still the exact
  // artifact; a ready marker alone cannot hide erasure or changed bytes.
  await dependencies.storage.verifyStored(allocated, signal);
  signal.throwIfAborted();
  if (!allocated.ready) {
    receipt = parseInitialRetentionReceipt(
      await dependencies.repository.complete(
        ownerID,
        request,
        allocated.object_id,
        signal,
      ),
      ownerID,
      request,
      receipt,
    );
    signal.throwIfAborted();
    if (!receipt.items.find((value) => value.media_id === media)?.ready) {
      return invalidHistory();
    }
  }
  return Object.freeze({ schema_version: 1 as const, ...receipt });
}

export function createInitialEvidenceUploadDependencies(): InitialEvidenceUploadDependencies {
  return {
    repository: createInitialEvidenceRepository(),
    storage: new PrivateHistoryEvidenceStorage(),
  };
}
