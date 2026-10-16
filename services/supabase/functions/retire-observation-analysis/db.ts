import type { SupabaseClient } from "@supabase/supabase-js";
import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  type AnalysisRetirementRequest,
  parseAnalysisRetirementRequest,
} from "../_shared/analysisHistory/executionRetirement.ts";

export function analysisRetirementRepository(client: SupabaseClient) {
  return {
    async retire(
      owner: string,
      input: AnalysisRetirementRequest,
      caller: AbortSignal,
    ): Promise<unknown> {
      const request = parseAnalysisRetirementRequest(input);
      const ownerID = historyUUID(owner);
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      try {
        signal.throwIfAborted();
        const result = client.rpc(
          "retire_owned_observation_analysis_execution",
          {
            p_owner: ownerID,
            p_request: request,
            p_reader: 10,
          },
        ).abortSignal(signal);
        // Regain control even if cancellation acknowledgement stalls. A lost
        // answer remains uncertain; this adapter never retries the mutation.
        let onAbort = () => {};
        const aborted = new Promise<never>((_, reject) => {
          onAbort = () =>
            reject(new HistoryError("analysis_history_unavailable"));
          signal.addEventListener("abort", onAbort, { once: true });
          if (signal.aborted) onAbort();
        });
        const { data, error } = await Promise.race([result, aborted]).finally(
          () => signal.removeEventListener("abort", onAbort),
        );
        if (error) {
          switch (error.message) {
            case "analysis_history_not_found":
            case "analysis_history_deleted":
            case "analysis_history_operation_conflict":
              throw new HistoryError(error.message);
            default:
              throw new HistoryError("analysis_history_unavailable");
          }
        }
        return data;
      } catch (error) {
        if (error instanceof HistoryError) throw error;
        throw new HistoryError("analysis_history_unavailable");
      }
    },
  };
}
