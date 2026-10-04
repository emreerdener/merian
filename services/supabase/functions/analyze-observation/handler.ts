import { parseExecutableAnalysisInput } from "../_shared/analysisHistory/analysisInput.ts";
import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import type { AnalysisState } from "../_shared/analysisHistory/execution.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export interface AnalyzeObservationDependencies {
  run(owner: string, input: Record<string, unknown>): Promise<AnalysisState>;
}
export async function analyzeObservation(
  req: Request,
  body: unknown,
  verifiedOwner: string,
  deps: AnalyzeObservationDependencies,
): Promise<Response> {
  try {
    const input = parseExecutableAnalysisInput(body);
    const state = await deps.run(historyUUID(verifiedOwner), input);
    return jsonResponse(
      {
        schema_version: 1,
        observation_id: input.observation_id,
        analysis_id: input.analysis_id,
        state,
      },
      state === "complete" || state === "failed_terminal" ? 200 : 202,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    const code = error instanceof HistoryError
      ? error.code
      : "analysis_history_unavailable";
    return publicErrorResponse(
      req,
      code === "invalid_analysis_history"
        ? 400
        : code === "analysis_history_not_found"
        ? 404
        : code === "analysis_history_operation_conflict"
        ? 409
        : 503,
      code,
      code === "analysis_history_operation_conflict"
        ? "This analysis identity conflicts with saved work. Recover the original request."
        : "Identification is not available yet. Retry with the same analysis.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
