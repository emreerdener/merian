import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError, invalidHistory } from "./contract.ts";
import { evidenceDigest } from "./evidence.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import type { PhotoCopyDependencies } from "./photoCopyExecution.ts";
import { erasePublicationPhoto } from "./photoErasure.ts";
import { executePublicationCopyMember } from "./publicationCopyExecution.ts";
import {
  type ApprovedCopyMember,
  publicationCopyRepository,
  type PublicationCopyWorkScope,
} from "./publicationCopyRepository.ts";
import { publicationAbortable } from "./publicationDeadline.ts";
import { validatePublicPhotoContainer } from "./publicPhotoContainer.ts";
import { PublicHistoryPhotoStorage } from "./publicPhotoStorage.ts";

export interface PublicationCopyOperationDependencies {
  erasure: {
    claim(objectId: string | null, signal: AbortSignal): Promise<unknown>;
    erase(objectId: string, signal: AbortSignal): Promise<void>;
    finish(
      objectId: string,
      claim: string,
      success: boolean,
      signal: AbortSignal,
    ): Promise<boolean>;
  };
  readSource?: PhotoCopyDependencies["readSource"];
  storage?: PhotoCopyDependencies["storage"];
  signal?: AbortSignal;
  now?: () => number;
  // Testable clocks only. Production uses the real abort timer for every phase.
  deadlineSignal?: (milliseconds: number) => AbortSignal;
}
/** One claimed operation, never a fresh lease per photo. This controller does
 * not discover/schedule work or claim durable terminal failure. The future
 * service owner must settle bounded needs-action reasons before exposing it. */
export async function executePublicationCopyOperation(
  client: SupabaseClient,
  identity: PublicationCopyWorkScope,
  members: readonly ApprovedCopyMember[],
  workExpiresAt: string,
  deps: PublicationCopyOperationDependencies,
): Promise<"published" | "reconcile"> {
  const now = deps.now ?? Date.now;
  const started = now(), workExpires = Date.parse(workExpiresAt);
  if (!Number.isFinite(workExpires)) {
    return invalidHistory();
  }
  const timeout = deps.deadlineSignal ?? AbortSignal.timeout;
  const overall = AbortSignal.any([
    timeout(110_000),
    ...(deps.signal ? [deps.signal] : []),
  ]);
  // Reserve 30s for the final binding/read recovery/targeted cleanup. A claim's
  // elapsed time is never renewed by entering this function or starting a photo.
  const freshUntil = Math.min(started + 80_000, workExpires - 30_000);
  const fresh = AbortSignal.any([
    overall,
    timeout(Math.max(0, Math.floor(freshUntil - started))),
  ]);
  const bindSignal = AbortSignal.any([
    overall,
    timeout(
      Math.max(
        0,
        Math.floor(Math.min(started + 92_000, workExpires) - started),
      ),
    ),
  ]);
  const repo = publicationCopyRepository(client, identity, members, overall);
  // These frozen source/scope values, not caller-owned input, drive later I/O.
  const photos = members.map((m) => repo.forPhoto(m.attempt_id));
  const verified = new Map<string, Uint8Array>();
  const privateStorage = new PrivateHistoryEvidenceStorage();
  const publicStorage = deps.storage ?? new PublicHistoryPhotoStorage();
  const checkFresh = () => {
    fresh.throwIfAborted();
    if (now() >= freshUntil) {
      throw new HistoryError("analysis_history_unavailable");
    }
  };
  const boundedErasure: PhotoCopyDependencies["erasure"] = {
    claim: (id) =>
      publicationAbortable(overall, () => deps.erasure.claim(id, overall)),
    erase: (id) =>
      publicationAbortable(overall, () => deps.erasure.erase(id, overall)),
    finish: (id, claim, success) =>
      publicationAbortable(
        overall,
        () => deps.erasure.finish(id, claim, success, overall),
      ),
  };
  async function recover() {
    try {
      return (await repo.read()).publication !== null;
    } catch {
      return false;
    }
  }
  async function cleanup() {
    // A missing binding response is not evidence of failure. Read its durable
    // receipt first; the registry independently vetoes erasure of bound objects.
    if (await recover()) return "published" as const;
    for (const target of await repo.cleanupTargets()) {
      try {
        await erasePublicationPhoto(boundedErasure, target);
      } catch { /* Permanent registry retains deadline/crash cleanup. */ }
    }
    return "reconcile" as const;
  }
  try {
    if ((await repo.read()).publication) return "published";
    checkFresh();
    // Whole-cohort permission and cleanup intent must precede private/public I/O.
    await repo.reserve();
    checkFresh();
    try {
      for (const photo of photos) {
        checkFresh();
        const bytes = (await publicationAbortable(fresh, () =>
          (deps.readSource ?? ((s, signal) =>
            privateStorage.readVerified(s, signal)))(photo.source, fresh)))
          .slice();
        checkFresh();
        if (
          bytes.byteLength !== photo.source.byte_count ||
          await evidenceDigest(bytes) !== photo.source.sha256
        ) {
          throw new HistoryError("analysis_history_evidence_unavailable");
        }
        validatePublicPhotoContainer(bytes, photo.source.content_type);
        checkFresh();
        verified.set(photo.source.media_id, bytes);
      }
    } catch {
      return await cleanup();
    }
    for (const photo of photos) {
      checkFresh();
      const result = await executePublicationCopyMember(
        repo,
        photo.scope.attempt_id,
        {
          now,
          deadlineSignal: (ms) => AbortSignal.any([fresh, timeout(ms)]),
          readSource: (source) => {
            checkFresh();
            const bytes = verified.get(source.media_id);
            if (!bytes) {
              throw new HistoryError("analysis_history_evidence_unavailable");
            }
            return Promise.resolve(bytes);
          },
          storage: {
            writeOnce: (target, bytes, signal) =>
              publicationAbortable(
                signal ?? fresh,
                () => publicStorage.writeOnce(target, bytes, signal ?? fresh),
              ),
          },
          erasure: boundedErasure,
        },
      );
      verified.delete(photo.source.media_id);
      if (result !== "ready") return await cleanup();
    }
    bindSignal.throwIfAborted();
    if (now() >= Math.min(started + 92_000, workExpires)) {
      return await cleanup();
    }
    await repo.bind(bindSignal);
    return "published";
  } catch {
    return await cleanup();
  } finally {
    verified.clear();
  }
}
