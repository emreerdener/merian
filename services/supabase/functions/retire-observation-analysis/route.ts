import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../_shared/serviceRoleClient.ts";
import { analysisRetirementRepository } from "./db.ts";
import { retireObservationAnalysis } from "./handler.ts";

export function analysisRetirementRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small", maxBytes: 2048 });
    if (body instanceof Response) return body;
    // This mutation has a scoped deadline and actual streamed response cap.
    // A timeout can conceal a commit; only exact operation replay recovers it.
    const client = createServiceRoleClientFromEnvironmentWithOptions({
      requestTimeoutMs: 5_000,
      maximumResponseBytes: 4096,
    });
    return retireObservationAnalysis(
      req,
      body,
      user.id,
      analysisRetirementRepository(client),
    );
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
