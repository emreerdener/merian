import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";
import type { eraseObservationEvidence } from "./handler.ts";

type Counts = Awaited<ReturnType<typeof eraseObservationEvidence>>;

/** Called only after service authentication. Correlation confers no authority. */
export async function evidenceWorkerReceipt(
  req: Request,
  work: () => Promise<Counts>,
): Promise<Response> {
  const headers = { "Cache-Control": "no-store" };
  const dispatch = req.headers.get("X-Merian-Evidence-Dispatch");
  if (
    dispatch !== null &&
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
  const counts = await work();
  // Legacy callers retain the closed six-counter shape. Only terminal work
  // echoes correlation; errors must never look like a completed invocation.
  return jsonResponse(
    dispatch === null
      ? counts
      : { schema_version: 2, dispatch_id: dispatch, ...counts },
    200,
    headers,
  );
}
