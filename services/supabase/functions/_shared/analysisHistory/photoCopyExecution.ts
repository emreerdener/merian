import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { type PublicationPhotoSource } from "./photoClassifier.ts";
import {
  erasePublicationPhoto,
  type PhotoErasureDependencies,
} from "./photoErasure.ts";
import { validatePublicPhotoContainer } from "./publicPhotoContainer.ts";
import { PublicHistoryPhotoStorage } from "./publicPhotoStorage.ts";

export interface PhotoCopyScope {
  readonly owner_id: string;
  readonly observation_id: string;
  readonly attempt_id: string;
}
export interface PhotoCopyLease extends PhotoCopyScope {
  readonly object_id: string;
  readonly lease_token: string;
}
export interface PhotoCopyDependencies {
  // SQL must freshly authorize the approved attempt and exact source. These
  // callbacks never create another moderation attempt or extend staging time.
  reserve(scope: PhotoCopyScope): Promise<unknown>;
  complete(scope: PhotoCopyLease, signal: AbortSignal): Promise<unknown>;
  abandon(scope: PhotoCopyLease): Promise<void>;
  erasure: PhotoErasureDependencies;
  readSource?: (
    source: Readonly<PublicationPhotoSource>,
    signal: AbortSignal,
  ) => Promise<Uint8Array>;
  storage?: Pick<PublicHistoryPhotoStorage, "writeOnce">;
  now?: () => number;
  deadlineSignal?: (timeoutMs: number) => AbortSignal;
}

function sourceFacts(value: unknown): Readonly<PublicationPhotoSource> {
  const row = exactObject(value, [
    "media_id",
    "object_id",
    "content_type",
    "byte_count",
    "sha256",
  ]);
  const media = historyUUID(row.media_id), object = historyUUID(row.object_id);
  if (
    media === object ||
    (row.content_type !== "image/jpeg" && row.content_type !== "image/png") ||
    typeof row.byte_count !== "number" ||
    !Number.isSafeInteger(row.byte_count) ||
    row.byte_count < 1 || row.byte_count > 12 * 1024 * 1024 ||
    typeof row.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(row.sha256)
  ) return invalidHistory();
  return Object.freeze({
    media_id: media,
    object_id: object,
    content_type: row.content_type,
    byte_count: row.byte_count,
    sha256: row.sha256,
  });
}

function copyReceipt(
  value: unknown,
  scope: PhotoCopyScope,
  source: Readonly<PublicationPhotoSource>,
) {
  const row = exactObject(value, [
    "attempt_id",
    "object_id",
    "observation_id",
    "owner_id",
    "source",
    "lease_token",
    "expires_at",
    "ready_at",
  ]);
  const saved = sourceFacts(row.source);
  if (
    row.owner_id !== scope.owner_id ||
    row.observation_id !== scope.observation_id ||
    row.attempt_id !== scope.attempt_id ||
    Object.keys(source).some((key) =>
      saved[key as keyof PublicationPhotoSource] !==
        source[key as keyof PublicationPhotoSource]
    ) ||
    typeof row.expires_at !== "string" ||
    !Number.isFinite(Date.parse(row.expires_at)) ||
    (row.ready_at !== null &&
      (typeof row.ready_at !== "string" ||
        !Number.isFinite(Date.parse(row.ready_at))))
  ) return invalidHistory();
  const object = historyUUID(row.object_id),
    token = historyUUID(row.lease_token);
  if (
    [
      scope.owner_id,
      scope.observation_id,
      scope.attempt_id,
      source.media_id,
      source.object_id,
    ].includes(object)
  ) {
    return invalidHistory();
  }
  return Object.freeze({
    lease: Object.freeze({ ...scope, object_id: object, lease_token: token }),
    expires_at: row.expires_at,
    ready_at: row.ready_at,
  });
}

/** One approved source, one durable reservation, no publication or provider call.
 * `reconcile` requires the operation owner to read durable state, including any
 * successful cohort receipt, before deciding whether an explicit new intent is
 * needed. It is never permission to loop or allocate a successor. */
export async function executePublicationPhotoCopy(
  identity: PhotoCopyScope,
  approvedSource: PublicationPhotoSource,
  deps: PhotoCopyDependencies,
): Promise<"ready" | "reconcile"> {
  const scope: PhotoCopyScope = Object.freeze({
    owner_id: historyUUID(identity.owner_id),
    observation_id: historyUUID(identity.observation_id),
    attempt_id: historyUUID(identity.attempt_id),
  });
  const source = sourceFacts(approvedSource);
  let receipt: ReturnType<typeof copyReceipt>;
  try {
    // Durable cleanup obligation must exist before source or destination I/O.
    receipt = copyReceipt(await deps.reserve(scope), scope, source);
  } catch {
    // A lost reservation response is recovered by the same attempt later. No
    // object from an unvalidated response may be written, abandoned or erased.
    return "reconcile";
  }
  const now = deps.now ?? Date.now;
  const expires = Date.parse(receipt.expires_at);
  const remaining = Math.min(60_000, expires - now());
  if (!Number.isFinite(remaining) || remaining <= 0) return await cleanup();
  // One shared deadline, never a fresh budget per read/write or final retry.
  const signal = (deps.deadlineSignal ?? AbortSignal.timeout)(
    Math.floor(remaining),
  );
  const checkDeadline = () => {
    signal.throwIfAborted();
    if (now() >= expires) throw new Error("publication_photo_copy_expired");
  };
  try {
    checkDeadline();
    if (receipt.ready_at !== null) return "ready";
    const storage = new PrivateHistoryEvidenceStorage();
    const bytes = (await (deps.readSource ?? ((s, signal) =>
      storage.readVerified(s, signal)))(source, signal)).slice();
    checkDeadline();
    if (
      bytes.byteLength !== source.byte_count ||
      await evidenceDigest(bytes) !== source.sha256
    ) {
      return await cleanup();
    }
    validatePublicPhotoContainer(bytes, source.content_type);
    checkDeadline();
    await (deps.storage ?? new PublicHistoryPhotoStorage()).writeOnce(
      {
        object_id: receipt.lease.object_id,
        source,
      },
      bytes,
      signal,
    );
    // Retry only the identical completion, never the public write in this call.
    for (let n = 0; n < 2; n++) {
      try {
        checkDeadline();
        const completed = copyReceipt(
          await deps.complete(receipt.lease, signal),
          scope,
          source,
        );
        checkDeadline();
        if (
          completed.lease.object_id === receipt.lease.object_id &&
          completed.lease.lease_token === receipt.lease.lease_token &&
          completed.expires_at === receipt.expires_at &&
          completed.ready_at !== null
        ) {
          return "ready";
        }
      } catch {
        /* Completion may have committed despite the missing reply. */
      }
    }
  } catch { /* Storage uncertainty must retain cleanup, never publication. */ }
  return await cleanup();

  async function cleanup(): Promise<"reconcile"> {
    try {
      await deps.abandon(receipt.lease);
    } catch { /* Deletion may already have cascaded the private receipt. */ }
    try {
      // Always request the registry claim, even after failed abandonment. The
      // claim alone authorizes erasure; a valid bound publication returns none.
      await erasePublicationPhoto(deps.erasure, receipt.lease.object_id);
    } catch { /* The permanent registry retains expiry/crash recovery. */ }
    return "reconcile";
  }
}
