import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import {
  parseSourceReservationRequest,
  SOURCE_RESERVATION_MAX_RECEIPT_BYTES,
  SOURCE_RESERVATION_MAX_REQUEST_BYTES,
} from "../_shared/analysisHistory/sourceReservation.ts";
import { sourceReservationRepository } from "../_shared/analysisHistory/sourceReservationRepository.ts";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../_shared/serviceRoleClient.ts";

/** Reserves original source occupancy only; never admits or dispatches inference. */
export function sourceReservationRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, {
      limit: "standard",
      maxBytes: SOURCE_RESERVATION_MAX_REQUEST_BYTES,
    });
    if (body instanceof Response) return body;
    try {
      // Validate before constructing the privileged client. No payload owner is accepted.
      const candidate = await parseSourceReservationRequest(body);
      const client = createServiceRoleClientFromEnvironmentWithOptions({
        requestTimeoutMs: 5_000,
        maximumResponseBytes: SOURCE_RESERVATION_MAX_RECEIPT_BYTES,
      });
      const receipt = await sourceReservationRepository(client).reserve(
        user.id,
        candidate,
        req.signal,
      );
      return jsonResponse(receipt, 200, {
        "Cache-Control": "private, no-store",
      });
    } catch (error) {
      const invalid = error instanceof HistoryError &&
        error.code === "invalid_analysis_history";
      const conflict = error instanceof HistoryError &&
        error.code === "analysis_history_operation_conflict";
      return publicErrorResponse(
        req,
        invalid ? 400 : conflict ? 409 : 503,
        invalid
          ? "invalid_analysis_history"
          : conflict
          ? "analysis_history_operation_conflict"
          : "analysis_history_unavailable",
        "Source reservation is unavailable.",
        { extraHeaders: { "Cache-Control": "private, no-store" } },
      );
    }
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
