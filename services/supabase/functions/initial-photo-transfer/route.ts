/** Source-only composition. Deliberately no serveEdge/index or deployment entry. */
import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { allocationRepository } from "../initial-photo-allocation/db.ts";
import { createCpmPhotoClosureDb } from "../_shared/initialAnalysis/cpmPhotoClosureDb.ts";
import { TRANSFER_BODY_LIMIT } from "./contract.ts";
import { initialPhotoTransfer, type TransferDependencies } from "./handler.ts";
import type { TransferPolicyCatalog } from "./catalog.ts";

export function initialPhotoTransferRoute(
  req: Request,
  catalog: TransferPolicyCatalog,
  authenticate?: EdgeAuthenticator,
  dependencies?: () => TransferDependencies,
): Promise<Response> {
  return withEdgeHandler(req, async (user) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, {
      limit: "bulk",
      maxBytes: TRANSFER_BODY_LIMIT,
    });
    if (body instanceof Response) return body;
    return initialPhotoTransfer(
      req,
      body,
      user.id,
      () => {
        if (dependencies) return dependencies();
        const bridge = createCpmPhotoClosureDb(null);
        return {
          catalog,
          bridge,
          progress: bridge,
          recover: (owner, request, signal) =>
            allocationRepository().call(owner, request, signal),
        };
      },
    );
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
