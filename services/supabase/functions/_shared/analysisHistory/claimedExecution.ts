import type { AIAttemptSnapshot, AIExecutionOutcome } from "../ai/contracts.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import type { ResolvedAnalysisSpecies } from "./append.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import type {
  AnalysisExecutionDependencies,
  AnalysisState,
  AnalysisWork,
  SavedAnalysisOutcome,
} from "./execution.ts";

export type ClaimedHistoryWork = Omit<AnalysisWork, "provider_outcome"> & {
  provider_outcome?: unknown;
};

/** Internal policies supplied by a lane owner, never by request JSON. Claims,
 * saved input and quota still require that lane's closed service decoder. */
export interface ClaimedHistoryPolicy {
  parseInput(value: unknown): Record<string, unknown>;
  assertSnapshot(work: AnalysisWork, snapshot: AIAttemptSnapshot): unknown;
  captureOutcome(
    result: AIExecutionOutcome,
    work: AnalysisWork,
  ): SavedAnalysisOutcome | null;
  buildDraft(
    inputBytes: string,
    result: unknown,
    species: ResolvedAnalysisSpecies | null,
  ): unknown;
}

/** Shared claimed-work sequencing. Only a proven dispatch grant invokes AI;
 * retained outcomes resume without inference. This helper grants no claim. */
export async function executeClaimedHistoryAnalysis(
  work: ClaimedHistoryWork,
  deps: AnalysisExecutionDependencies,
  policy: ClaimedHistoryPolicy,
  signal?: AbortSignal,
): Promise<AnalysisState> {
  if (!work.claimed) return work.state;
  const input = policy.parseInput(work.input);
  historyUUID(work.work_token);
  if (!work.quota) return invalidHistory();
  let state = work.state;
  try {
    let saved = work.provider_outcome;
    if (state === "admitted") {
      signal?.throwIfAborted();
      const dispatchWork: AnalysisWork = {
        state: work.state,
        claimed: true,
        work_token: work.work_token,
        input,
        quota: work.quota,
      };
      const prepared = await deps.prepare(dispatchWork);
      policy.assertSnapshot(dispatchWork, prepared.snapshot);
      signal?.throwIfAborted();
      const response = await deps.advance("dispatch", {
        provenance: identificationProvenance(prepared.snapshot),
      });
      const dispatch = exactObject(response, ["invocation_id", "may_dispatch"]);
      historyUUID(dispatch.invocation_id);
      if (typeof dispatch.may_dispatch !== "boolean") return invalidHistory();
      state = "dispatched";
      if (!dispatch.may_dispatch) return state;
      signal?.throwIfAborted();
      const result = await prepared.invoke();
      saved = policy.captureOutcome(result, dispatchWork);
      if (!saved) return state;
      await deps.advance("outcome", {
        quota_token: historyUUID(work.quota.lease_token),
        value: saved,
      });
    }
    if (state === "dispatched") {
      if (!saved) return state;
      const received = exactObject(saved, [
        "schema_version",
        "provenance",
        "outcome",
        "usage",
      ]);
      if (received.schema_version !== 1) return invalidHistory();
      const kind = received.outcome && typeof received.outcome === "object" &&
          "kind" in received.outcome
        ? received.outcome.kind
        : null;
      const outcome = exactObject(
        received.outcome,
        kind === "draft" ? ["kind", "result"] : ["kind"],
      );
      if (
        kind === "refusal" ||
        kind === "invalid_output"
      ) {
        await deps.advance("fail", {});
        return "failed_terminal";
      }
      if (kind !== "draft") return invalidHistory();

      const result = parseIdentifySuccessEnvelope({
        success: true,
        data: outcome.result,
      }).data;
      const species = await deps.resolveSpecies(result);
      const draft = policy.buildDraft(
        JSON.stringify(input),
        result,
        species,
      );
      await deps.advance("draft", { draft });
      await deps.advance("account", {});
      state = "draft";
    }
    if (state === "draft") {
      await deps.advance("complete", {});
      return "complete";
    }
    return state;
  } finally {
    // Await cleanup of this lease only. SQL refuses a replaced or expired token;
    // release cannot erase evidence, settle credits or mask the original error.
    await deps.advance("release", {}).catch(() => {});
  }
}
