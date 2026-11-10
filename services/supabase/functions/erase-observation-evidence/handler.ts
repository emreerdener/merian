import {
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";

export interface EvidenceErasureDependencies {
  retire(signal: AbortSignal): Promise<unknown>;
  retireVideo(signal: AbortSignal): Promise<unknown>;
  claim(signal: AbortSignal): Promise<unknown>;
  erase(object: string, signal: AbortSignal): Promise<void>;
  finish(
    object: string,
    token: string,
    success: boolean,
    signal: AbortSignal,
  ): Promise<boolean>;
  now?: () => number;
  wallNow?: () => number;
  timeout?: (milliseconds: number) => AbortSignal;
}

/** One retirement per media lane and one marker; no renewed claims or retries. */
export async function eraseObservationEvidence(
  deps: EvidenceErasureDependencies,
  parent?: AbortSignal,
) {
  const now = deps.now ?? (() => performance.now());
  const wallNow = deps.wallNow ?? Date.now;
  const timeout = deps.timeout ?? AbortSignal.timeout;
  const requestEnd = now() + 90_000;
  const overall = AbortSignal.any([
    timeout(90_000),
    ...(parent ? [parent] : []),
  ]);
  const stage = (ms: number, end = requestEnd) => {
    const remaining = Math.floor(Math.min(ms, end - now(), requestEnd - now()));
    if (remaining <= 0) throw new Error("private_evidence_erasure_unavailable");
    overall.throwIfAborted();
    return AbortSignal.any([overall, timeout(remaining)]);
  };
  const counts = {
    retired: 0,
    video_retired: 0,
    retirement_failures: 0,
    claimed: 0,
    marked: 0,
    acknowledged: 0,
  };
  // Each independently authorized SQL owner gets one bounded opportunity. A
  // held or unavailable lane cannot starve another media lane or obligations
  // already in the durable registry. Unknown acknowledgements are not retried.
  for (
    const lane of [
      { key: "retired", maximum: 5, run: deps.retire },
      { key: "video_retired", maximum: 7, run: deps.retireVideo },
    ] as const
  ) {
    overall.throwIfAborted();
    try {
      const signal = stage(12_000);
      const retired = await publicationAbortable(
        signal,
        () => lane.run(signal),
      );
      if (
        typeof retired !== "number" || !Number.isSafeInteger(retired) ||
        retired < 0 || retired > lane.maximum
      ) throw new Error("private_evidence_erasure_unavailable");
      counts[lane.key] = retired;
    } catch {
      // No SQL/provider error detail leaves this boundary. Cancellation still
      // stops all subsequent work; an independent stage timeout is observable.
      overall.throwIfAborted();
      counts.retirement_failures++;
    }
  }
  overall.throwIfAborted();
  // Do not acquire a new lease when even an on-time claim response could not
  // leave the existing marker/settlement reserve. Zero claims is not an empty
  // registry assertion; the read-only health projection owns backlog evidence.
  if (requestEnd - now() < 50_000) return counts;
  const claimStart = now();
  const claimSignal = stage(12_000);
  const value = await publicationAbortable(
    claimSignal,
    () => deps.claim(claimSignal),
  );
  if (value === null) return counts;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const row = value as Record<string, unknown>;
  if (
    Object.keys(row).length !== 3 || !Object.hasOwn(row, "object_id") ||
    !Object.hasOwn(row, "claim_token") ||
    !Object.hasOwn(row, "claim_expires_at") ||
    typeof row.claim_expires_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(row.claim_expires_at) ||
    !Number.isFinite(Date.parse(row.claim_expires_at))
  ) return invalidHistory();
  // Own primitive identities across awaits, even if the repository mutates its row.
  const object = historyUUID(row.object_id),
    token = historyUUID(row.claim_token);
  const claimEnd = Math.min(
    requestEnd,
    claimStart + 60_000,
    now() + Date.parse(row.claim_expires_at) - wallNow(),
  );
  counts.claimed = 1;
  try {
    // 25s for PUT+HEAD, 12s settlement and 1s scheduling margin. A late claim
    // reply cannot consume the original lease's completion reserve.
    if (claimEnd - now() >= 38_000) {
      const storageSignal = stage(25_000, claimEnd - 13_000);
      await publicationAbortable(
        storageSignal,
        () => deps.erase(object, storageSignal),
      );
      storageSignal.throwIfAborted();
      counts.marked = 1;
    }
  } catch { /* Permanent outbox retains uncertain marker work. */ }
  try {
    const finishSignal = stage(12_000, claimEnd);
    counts.acknowledged = await publicationAbortable(finishSignal, () =>
        deps.finish(object, token, counts.marked === 1, finishSignal)) === true
      ? 1
      : 0;
  } catch { /* Expiry recovers unknown acknowledgement; never retry here. */ }
  return counts;
}
