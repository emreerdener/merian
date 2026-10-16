import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  type AnalysisRetirementRequest,
  parseAnalysisRetirementReceipt,
  parseAnalysisRetirementRequest,
} from "../_shared/analysisHistory/executionRetirement.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export async function retireObservationAnalysis(
  req: Request,
  body: unknown,
  owner: string,
  deps: {
    retire(
      owner: string,
      request: AnalysisRetirementRequest,
      signal: AbortSignal,
    ): Promise<unknown>;
  },
): Promise<Response> {
  try {
    const request = parseAnalysisRetirementRequest(body);
    const data = await deps.retire(historyUUID(owner), request, req.signal);
    let receipt;
    try {
      receipt = parseAnalysisRetirementReceipt(data, request);
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
    return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    const original = error instanceof HistoryError
      ? error.code
      : "analysis_history_unavailable";
    const code = original === "analysis_history_deleted"
      ? "analysis_history_not_found"
      : original;
    const status = code === "invalid_analysis_history"
      ? 400
      : code === "analysis_history_not_found"
      ? 404
      : code === "analysis_history_operation_conflict"
      ? 409
      : 503;
    return publicErrorResponse(
      req,
      status,
      code,
      "Analysis retirement is unavailable.",
      {
        extraHeaders: { "Cache-Control": "private, no-store" },
      },
    );
  }
}
