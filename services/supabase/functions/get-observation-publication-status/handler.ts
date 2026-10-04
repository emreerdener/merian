import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  parsePublicationStatusReceipt,
  parsePublicationStatusRequest,
  type PublicationStatusRequest,
} from "../_shared/analysisHistory/publicationStatus.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export async function getObservationPublicationStatus(
  req: Request,
  body: unknown,
  owner: string,
  deps: {
    read(owner: string, request: PublicationStatusRequest): Promise<unknown>;
  },
): Promise<Response> {
  try {
    const request = parsePublicationStatusRequest(body);
    const data = await deps.read(historyUUID(owner), request);
    let receipt;
    try {
      receipt = parsePublicationStatusReceipt(data, request);
    } catch {
      throw new HistoryError("analysis_history_unavailable");
    }
    return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    const original = error instanceof HistoryError
      ? error.code
      : "analysis_history_unavailable";
    // A missing, foreign or deleted operation has one opaque public response.
    const code = original === "analysis_history_deleted"
      ? "analysis_history_not_found"
      : original;
    const status = code === "invalid_analysis_history"
      ? 400
      : code === "analysis_history_not_found"
      ? 404
      : code === "analysis_history_revision_conflict" ||
          code === "analysis_history_operation_conflict"
      ? 409
      : 503;
    return publicErrorResponse(
      req,
      status,
      code,
      "Publication status is unavailable.",
      {
        extraHeaders: { "Cache-Control": "private, no-store" },
      },
    );
  }
}
