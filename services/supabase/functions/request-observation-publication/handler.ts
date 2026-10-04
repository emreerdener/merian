import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  parsePublicationOperationReceipt,
  parsePublicationOperationRequest,
  type PublicationOperationRequest,
} from "../_shared/analysisHistory/publicationOperation.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";
export async function requestObservationPublication(
  req: Request,
  body: unknown,
  owner: string,
  deps: {
    admit(owner: string, input: PublicationOperationRequest): Promise<unknown>;
  },
): Promise<Response> {
  try {
    const request = parsePublicationOperationRequest(body);
    const result = await deps.admit(historyUUID(owner), request);
    let receipt;
    try {
      receipt = parsePublicationOperationReceipt(result, request);
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
    return jsonResponse(receipt, 202, { "Cache-Control": "private, no-store" });
  } catch (error) {
    const code = error instanceof HistoryError
      ? error.code
      : "analysis_history_unavailable";
    const status = code === "invalid_analysis_history"
      ? 400
      : code === "analysis_history_not_found" ||
          code === "analysis_history_deleted"
      ? 404
      : code === "analysis_history_operation_conflict" ||
          code === "analysis_history_revision_conflict"
      ? 409
      : 503;
    return publicErrorResponse(
      req,
      status,
      code,
      "Publication is not available. Recover the same operation before trying again.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
