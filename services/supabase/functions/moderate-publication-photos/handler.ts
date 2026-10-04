import type { PublicationPhotoSource } from "../_shared/analysisHistory/photoClassifier.ts";
import { preparePublicationPhotoCohort } from "../_shared/analysisHistory/photoCohortPreflight.ts";
import { executePublicationPhotoModeration } from "../_shared/analysisHistory/photoExecution.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import {
  isActivePhotoWork,
  type publicationModerationRepository,
  type PublicationWorkScope,
} from "../_shared/analysisHistory/publicationModerationRepository.ts";

export interface PublicationHint {
  owner_id: string;
  observation_id: string;
  operation_id: string;
}
export interface PublicationClaim {
  scope: PublicationWorkScope;
  sources: readonly PublicationPhotoSource[];
}
export interface PublicationModerationDependencies {
  list(signal: AbortSignal): Promise<readonly PublicationHint[]>;
  claim(
    hint: PublicationHint,
    signal: AbortSignal,
  ): Promise<PublicationClaim | null>;
  release(work: PublicationClaim, signal: AbortSignal): Promise<void>;
  repository(
    work: PublicationClaim,
    deadlines: {
      signal: AbortSignal;
      freshSignal: AbortSignal;
      canDispatch: () => boolean;
    },
  ): ReturnType<typeof publicationModerationRepository>;
  preflight?: typeof preparePublicationPhotoCohort;
  now?: () => number;
}
/** One durable operation and at most one provider invocation. Nothing is
 * scheduled or published; only SQL determines terminal historical outcomes. */
export async function moderatePublicationPhotos(
  deps: PublicationModerationDependencies,
) {
  const now = deps.now ?? (() => performance.now());
  const started = now();
  const signal = AbortSignal.timeout(135_000);
  const freshSignal = AbortSignal.any([signal, AbortSignal.timeout(105_000)]);
  const remaining = () => 105_000 - (now() - started);
  const counts = { claimed: 0, settled: 0 };
  const hints = await publicationAbortable(signal, () => deps.list(signal));
  if (!hints.length) return counts;
  const work = await publicationAbortable(
    signal,
    () => deps.claim(hints[0], signal),
  );
  if (!work) return counts;
  counts.claimed = 1;
  try {
    const repo = deps.repository(work, {
      signal,
      freshSignal,
      canDispatch: () => remaining() >= 27_000 && !freshSignal.aborted,
    });
    const recovered = await repo.read();
    if (await repo.finalize()) {
      counts.settled = 1;
      return counts;
    }
    // Retire only original dispatched attempts. SQL rejects retirement until
    // their provider lease expires. Never reconstruct a dispatch permit.
    const dispatched = recovered.find((r) => r?.state === "dispatched");
    if (dispatched && isActivePhotoWork(dispatched)) {
      await executePublicationPhotoModeration(
        work.scope,
        dispatched,
        repo.execution(dispatched),
      );
    } else {
      const refused = recovered.some((r) =>
        r && ["rejected", "unknown_execution", "cancelled"].includes(r.state)
      );
      const reserved = recovered.find((r) => r?.state === "reserved");
      if (refused) {
        // A prior refusal closes the cohort only after existing reservations
        // settle. Cancel one proven undispatched original reservation per pass.
        if (reserved && isActivePhotoWork(reserved)) {
          await repo.execution(reserved).retire({
            owner_id: work.scope.owner_id,
            observation_id: work.scope.observation_id,
            attempt_id: reserved.attempt_id,
            lease_token: reserved.lease_token,
          });
        }
      } else {
        const index = reserved
          ? recovered.indexOf(reserved)
          : recovered.findIndex((r) => r === null);
        if (index >= 0 && remaining() >= 60_000) {
          const cohort = await publicationAbortable(
            freshSignal,
            () =>
              (deps.preflight ?? preparePublicationPhotoCohort)(work.sources, {
                signal: freshSignal,
                providerSignal: freshSignal,
              }),
          );
          const prepared = await publicationAbortable(
            freshSignal,
            () => cohort.prepare(work.sources[index].media_id),
          );
          // Admission/proof/dispatch can each consume 12s. Do not reserve unless
          // there is still a useful provider window after those operations.
          if (remaining() >= 60_000 && !freshSignal.aborted) {
            const attempt = reserved ??
              await repo.admit(work.sources[index].media_id);
            if (isActivePhotoWork(attempt)) {
              await executePublicationPhotoModeration(work.scope, attempt, {
                ...repo.execution(attempt),
                prepare: () => Promise.resolve(prepared),
              });
            }
          }
        }
      }
      // Terminal decisions never trigger another photo's paid admission here.
    }
    if (await repo.finalize()) counts.settled = 1;
  } catch {
    // Durable state, provider lease and fixed backoff own recovery. Never return
    // evidence, notes, IP, provider diagnostics, tokens or attempt identities.
  } finally {
    try {
      await publicationAbortable(signal, () => deps.release(work, signal));
    } catch {
      /* Outcome may remove work, or expiry must recover a lost reply. */
    }
  }
  return counts;
}
