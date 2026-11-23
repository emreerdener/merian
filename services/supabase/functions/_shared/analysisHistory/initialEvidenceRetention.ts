import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { EVIDENCE_MAX_BYTES, evidenceDigest } from "./evidence.ts";
import {
  initialEvidenceArtifacts,
  initialEvidenceDigest,
  parseInitialEvidenceManifest,
} from "./initialEvidenceManifest.ts";

export interface InitialRetentionRequest {
  readonly schema_version: 1;
  readonly scan_id: string;
  readonly generation: string;
  readonly evidence_digest: string;
  readonly evidence_manifest: ReturnType<typeof parseInitialEvidenceManifest>;
}
export interface InitialRetentionRepository {
  reserve(
    owner: string,
    request: InitialRetentionRequest,
    signal: AbortSignal,
  ): Promise<unknown>;
  complete(
    owner: string,
    request: InitialRetentionRequest,
    objectID: string,
    signal: AbortSignal,
  ): Promise<unknown>;
}
type StoredArtifact = ReturnType<typeof initialEvidenceArtifacts>[number] & {
  readonly object_id: string;
  readonly ready: boolean;
};
export interface InitialRetentionStorage {
  writeOnce(
    receipt: StoredArtifact,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<void>;
  readVerified(
    receipt: StoredArtifact,
    signal: AbortSignal,
  ): Promise<Uint8Array>;
}

/** Server-installed source owner, never a client-supplied URL or callback.
 * Opening must qualify the current owner, generation and artifact identity.
 * The lease keeps that source alive through the PUT; close releases the read
 * lease, not the durable original hold. Only one lease is opened at a time.
 */
export interface InitialRetentionSource {
  open(
    artifact: ReturnType<typeof initialEvidenceArtifacts>[number],
    signal: AbortSignal,
  ): Promise<{
    readonly bytes: Uint8Array;
    close(): Promise<void>;
  }>;
}

export async function initialRetentionRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "scan_id",
    "generation",
    "evidence_digest",
    "evidence_manifest",
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  const scan = historyUUID(row.scan_id),
    generation = historyUUID(row.generation);
  const manifest = parseInitialEvidenceManifest(
    row.evidence_manifest,
    scan,
    generation,
  );
  const submittedDigest = row.evidence_digest;
  // Parsing owns the entire immutable graph before the first await.
  const digest = await initialEvidenceDigest(manifest, scan, generation);
  if (submittedDigest !== digest) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    scan_id: scan,
    generation,
    evidence_digest: digest,
    evidence_manifest: manifest,
  });
}

/** Authenticated server receipt. Metadata cannot substitute for verified bytes,
 * and neither a receipt nor a ready artifact is a completed scan/result proof.
 */
export interface InitialRetentionReceipt {
  readonly owner_id: string;
  readonly scan_id: string;
  readonly generation: string;
  readonly evidence_digest: string;
  readonly items: readonly StoredArtifact[];
}
export function parseInitialRetentionReceipt(
  value: unknown,
  owner: string,
  request: InitialRetentionRequest,
  previous?: InitialRetentionReceipt,
): InitialRetentionReceipt {
  historyUUID(owner);
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "scan_id",
    "generation",
    "evidence_digest",
    "items",
  ]);
  const expected = initialEvidenceArtifacts(request.evidence_manifest);
  if (
    [request.scan_id, request.generation, ...expected.map((x) => x.media_id)]
      .includes(owner)
  ) return invalidHistory();
  if (
    row.schema_version !== 1 || row.owner_id !== owner ||
    row.scan_id !== request.scan_id || row.generation !== request.generation ||
    row.evidence_digest !== request.evidence_digest ||
    !Array.isArray(row.items) ||
    row.items.length !== expected.length
  ) return invalidHistory();
  const seen = new Set([
    owner,
    request.scan_id,
    request.generation,
    ...expected.map((x) => x.media_id),
  ]);
  const items = row.items.map((value, index) => {
    const wanted = expected[index];
    const item = exactObject(value, [
      ...Object.keys(wanted),
      "object_id",
      "ready",
    ]);
    const objectID = historyUUID(item.object_id);
    if (
      Object.entries(wanted).some(([k, v]) => item[k] !== v) ||
      typeof item.ready !== "boolean" || seen.has(objectID)
    ) return invalidHistory();
    seen.add(objectID);
    if (previous) {
      const prior = previous.items[index];
      if (
        !prior || prior.object_id !== objectID || (prior.ready && !item.ready)
      ) return invalidHistory();
    }
    return Object.freeze({ ...wanted, object_id: objectID, ready: item.ready });
  });
  if (
    previous &&
    (previous.evidence_digest !== request.evidence_digest ||
      previous.owner_id !== owner)
  ) return invalidHistory();
  return Object.freeze({
    owner_id: owner,
    scan_id: request.scan_id,
    generation: request.generation,
    evidence_digest: request.evidence_digest,
    items: Object.freeze(items),
  });
}

/** Runs in the existing ordinary ingestion owner before provider dispatch.
 * The repository allocates every object durably before the first PUT. A failed
 * or cancelled attempt leaves those allocations owned for retry/erasure; this
 * helper never deletes them or retries inference/funding.
 */
export async function retainInitialEvidence(
  owner: string,
  value: unknown,
  buffers: ReadonlyMap<string, Uint8Array>,
  repository: InitialRetentionRepository,
  storage: InitialRetentionStorage,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  if (
    buffers.size > 64 ||
    [...buffers.values()].reduce((sum, bytes) => sum + bytes.byteLength, 0) >
      EVIDENCE_MAX_BYTES
  ) return invalidHistory();
  // Copy inputs synchronously; caller mutation during hashing cannot change
  // admitted evidence or leave a manifest pointing at a later buffer.
  const owned = new Map([...buffers].map(([id, bytes]) => [id, bytes.slice()]));
  const request = await initialRetentionRequest(value);
  // V8 originals must use the sequential source-owner API, never this legacy
  // whole-graph Map path, even if a particular V8 graph happens to be small.
  if (request.evidence_manifest.schema_version !== 7) return invalidHistory();
  const artifacts = initialEvidenceArtifacts(request.evidence_manifest);
  if (owned.size !== artifacts.length) return invalidHistory();
  for (const item of artifacts) {
    const bytes = owned.get(item.media_id);
    if (
      !bytes || bytes.length !== item.byte_count ||
      await evidenceDigest(bytes) !== item.sha256
    ) return invalidHistory();
    signal.throwIfAborted();
  }
  return await retainFromSource(
    owner,
    request,
    {
      open(item) {
        const bytes = owned.get(item.media_id);
        if (!bytes) return invalidHistory();
        return Promise.resolve({ bytes, close: () => Promise.resolve() });
      },
    },
    repository,
    storage,
    signal,
  );
}

/** Bounded ordinary-original transport. Reserve the complete immutable graph
 * first, then open, verify and write one artifact at a time. Recovery of ready
 * objects requires storage readback but no remaining local source. A failed
 * read/PUT leaves the durable reservation owned for retry and erasure.
 * This helper grants neither provider execution nor original-release authority.
 */
export async function retainInitialEvidenceFromSource(
  owner: string,
  value: unknown,
  source: InitialRetentionSource,
  repository: InitialRetentionRepository,
  storage: InitialRetentionStorage,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = await initialRetentionRequest(value);
  signal.throwIfAborted();
  return await retainFromSource(
    owner,
    request,
    source,
    repository,
    storage,
    signal,
  );
}

async function retainFromSource(
  owner: string,
  request: InitialRetentionRequest,
  source: InitialRetentionSource,
  repository: InitialRetentionRepository,
  storage: InitialRetentionStorage,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  let receipt = parseInitialRetentionReceipt(
    await repository.reserve(owner, request, signal),
    owner,
    request,
  );
  signal.throwIfAborted();
  for (const item of receipt.items) {
    if (!item.ready) {
      await writeSourceArtifact(item, source, storage, signal);
    }
    signal.throwIfAborted();
    // Readback proves the exact object, including on recovery after a lost PUT.
    const retained = await storage.readVerified(item, signal);
    if (
      retained.length !== item.byte_count ||
      await evidenceDigest(retained) !== item.sha256
    ) return invalidHistory();
    signal.throwIfAborted();
    if (!item.ready) {
      receipt = parseInitialRetentionReceipt(
        await repository.complete(owner, request, item.object_id, signal),
        owner,
        request,
        receipt,
      );
      signal.throwIfAborted();
      if (!receipt.items.find((x) => x.object_id === item.object_id)?.ready) {
        return invalidHistory();
      }
    }
  }
  if (receipt.items.some((x) => !x.ready)) return invalidHistory();
  return Object.freeze({ request, receipt });
}

// Keep the source buffer and its defensive snapshot out of the readback scope.
// A larger successor manifest must not reintroduce a cohort-wide buffer Map.
async function writeSourceArtifact(
  item: StoredArtifact,
  source: InitialRetentionSource,
  storage: InitialRetentionStorage,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const lease = await source.open(item, signal);
  try {
    signal.throwIfAborted();
    // Reject unexpected size before copying or hashing. Manifest parsing owns
    // the role-specific limit; a source cannot enlarge it by returning bytes.
    if (lease.bytes.byteLength !== item.byte_count) return invalidHistory();
    const bytes = lease.bytes.slice();
    if (await evidenceDigest(bytes) !== item.sha256) return invalidHistory();
    signal.throwIfAborted();
    await storage.writeOnce(item, bytes, signal);
    signal.throwIfAborted();
  } finally {
    // Cancellation must still finish releasing the source reader. The owner
    // keeps the durable hold until the separate completed-observation proof.
    await lease.close();
  }
}
