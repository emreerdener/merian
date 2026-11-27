import {
  type IdentitySafeErrorDetails,
  logIdentitySafeError,
} from "../_shared/edgeHandler.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";
import type { eraseObservationEvidence } from "./handler.ts";

type Counts = Awaited<ReturnType<typeof eraseObservationEvidence>>;

/** Called after service authentication; SQL independently admits this dispatch. */
export async function evidenceWorkerReceipt(
  req: Request,
  work: (dispatch: string) => Promise<Counts>,
): Promise<Response> {
  const headers = { "Cache-Control": "no-store" };
  const dispatch = req.headers.get("X-Merian-Evidence-Dispatch");
  if (
    dispatch === null ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(
        dispatch,
      )
  ) {
    return publicErrorResponse(
      req,
      400,
      "invalid_dispatch_correlation",
      "Invalid dispatch correlation.",
      {
        extraHeaders: headers,
      },
    );
  }
  const counts = await work(dispatch);
  // Only terminal work echoes correlation. Legacy acquisition is denied by
  // both this boundary and the permanent old-RPC denial in the database.
  return jsonResponse(
    { schema_version: 4, dispatch_id: dispatch, ...counts },
    200,
    headers,
  );
}

/** The authenticated HTTP boundary; failures never become terminal receipts. */
export async function evidenceWorkerResponse(
  req: Request,
  work: (dispatch: string) => Promise<Counts>,
  report: (event: string, details: IdentitySafeErrorDetails) => void =
    logIdentitySafeError,
): Promise<Response> {
  try {
    return await evidenceWorkerReceipt(req, work);
  } catch {
    try {
      report("private_evidence_worker_failed", {
        stage: "worker",
        code: "worker_unavailable",
      });
    } catch { /* Diagnostics must not change the unavailable response. */ }
    return publicErrorResponse(
      req,
      503,
      "private_evidence_erasure_unavailable",
      "Private media cleanup is unavailable.",
      { extraHeaders: { "Cache-Control": "no-store" } },
    );
  }
}
