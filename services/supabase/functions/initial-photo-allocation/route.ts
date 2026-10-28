import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { ALLOCATION_BODY_LIMIT } from "./contract.ts";
import { allocationRepository } from "./db.ts";
import { initialPhotoAllocation } from "./handler.ts";

export function initialPhotoAllocationRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, {
      limit: "bulk",
      maxBytes: ALLOCATION_BODY_LIMIT,
    });
    if (body instanceof Response) return body;
    return initialPhotoAllocation(req, body, user.id, {
      call: (owner, request, signal) =>
        allocationRepository().call(owner, request, signal),
    });
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
