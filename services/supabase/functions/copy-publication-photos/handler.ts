import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import type {
  ApprovedCopyMember,
  PublicationCopyWorkScope,
} from "../_shared/analysisHistory/publicationCopyRepository.ts";

export interface CopyHint {
  owner_id: string;
  observation_id: string;
  operation_id: string;
}
export interface CopyClaim {
  scope: Readonly<PublicationCopyWorkScope>;
  cohort: readonly ApprovedCopyMember[];
  work_expires_at: string;
}
export type CopyFinalization = { status: "pending" | "admitted" } | {
  status: "needs_action";
  targets: readonly string[];
};
export interface CopyWorkerDependencies {
  list(signal: AbortSignal): Promise<readonly CopyHint[]>;
  claim(hint: CopyHint, signal: AbortSignal): Promise<CopyClaim | null>;
  finalize(work: CopyClaim, signal: AbortSignal): Promise<CopyFinalization>;
  execute(
    work: CopyClaim,
    signal: AbortSignal,
  ): Promise<"published" | "reconcile">;
  cleanup(targets: readonly string[], signal: AbortSignal): Promise<void>;
  release(work: CopyClaim, signal: AbortSignal): Promise<void>;
  now?: () => number;
  deadlineSignal?: (milliseconds: number) => AbortSignal;
}
/** One operation per request. SQL owns terminality; transport failure is recovery. */
export async function copyPublicationPhotos(deps: CopyWorkerDependencies) {
  const now = deps.now ?? (() => performance.now());
  const timeout = deps.deadlineSignal ?? AbortSignal.timeout;
  const started = now(), overall = timeout(135_000);
  // Stop all work with 12 seconds left for the exact lease's release.
  const action = AbortSignal.any([overall, timeout(123_000)]);
  const counts = { claimed: 0, published: 0, needs_action: 0 };
  const hints = await publicationAbortable(action, () => deps.list(action));
  if (!hints.length) return counts;
  const work = await publicationAbortable(
    action,
    () => deps.claim(hints[0], action),
  );
  if (!work) return counts;
  counts.claimed = 1;
  try {
    const result = await publicationAbortable(
      action,
      () => deps.finalize(work, action),
    );
    if (result.status === "admitted") counts.published = 1;
    else if (result.status === "needs_action") {
      counts.needs_action = 1;
      if (result.targets.length) {
        await publicationAbortable(
          action,
          () => deps.cleanup(result.targets, action),
        );
      }
    } else if (135_000 - (now() - started) >= 122_000 && !action.aborted) {
      // Do not truncate the controller's recovery/cleanup window to make slow
      // setup fit. Releasing work makes it eligible for a later bounded pass.
      if (
        await publicationAbortable(action, () => deps.execute(work, action)) ===
          "published"
      ) counts.published = 1;
    }
  } catch {
    /* Durable registry/work owns uncertain or interrupted recovery. */
  } finally {
    try {
      await publicationAbortable(overall, () => deps.release(work, overall));
    } catch {
      /* Work may already be retired; original expiry recovers lost replies. */
    }
  }
  return counts;
}
