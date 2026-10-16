import {
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";

export interface AnalysisRecoveryDependencies {
  list(): Promise<unknown>;
  recover(
    owner: string,
    observation: string,
    analysis: string,
  ): Promise<boolean>;
  now(): number;
}
/** A single bounded discovery pass; one bad/deleted job cannot starve the rest. */
export async function recoverObservationAnalyses(
  deps: AnalysisRecoveryDependencies,
  maximumCandidates: 10 | 32 = 10,
) {
  const deadline = deps.now() + 40_000;
  const candidates = await deps.list();
  if (!Array.isArray(candidates) || candidates.length > maximumCandidates) {
    return invalidHistory();
  }
  let attempted = 0, completed = 0;
  for (const item of candidates) {
    if (deps.now() >= deadline) break;
    attempted++;
    try {
      if (
        await deps.recover(
          historyUUID(item.owner_id),
          historyUUID(item.observation_id),
          historyUUID(item.analysis_id),
        )
      ) completed++;
    } catch {
      /* Retained result/hold and delayed retry; no private diagnostics. */
    }
  }
  return { attempted, completed };
}
