import {
  executePublicationPhotoCopy,
  type PhotoCopyDependencies,
} from "./photoCopyExecution.ts";
import { erasePublicationPhoto } from "./photoErasure.ts";
import type { publicationCopyRepository } from "./publicationCopyRepository.ts";

/** Cohort-aware bridge. Only the repository's validated/pinned original targets
 * can extend cleanup beyond the single-photo executor's own reserved object.
 * The caller must bound all erasure transports by the overall worker deadline. */
export async function executePublicationCopyMember(
  repository: ReturnType<typeof publicationCopyRepository>,
  attempt: string,
  transport: Omit<PhotoCopyDependencies, "reserve" | "complete" | "abandon">,
): Promise<"ready" | "reconcile"> {
  const photo = repository.forPhoto(attempt);
  return await executePublicationPhotoCopy(photo.scope, photo.source, {
    ...transport,
    reserve: photo.reserve,
    complete: photo.complete,
    async abandon(lease) {
      const targets = await photo.cleanupTargets(lease);
      for (const target of targets) {
        // The generic executor owns its original object's targeted cleanup.
        if (target === lease.object_id) continue;
        try {
          await erasePublicationPhoto(transport.erasure, target);
        } catch {
          /* Registry expiry retains cleanup if this pass runs out of time. */
        }
      }
    },
  });
}
