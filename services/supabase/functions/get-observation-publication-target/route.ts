import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { publicationTargetRepository } from "./db.ts";
import { getObservationPublicationTarget } from "./handler.ts";

export function publicationTargetRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small", maxBytes: 1024 });
    if (body instanceof Response) return body;
    return getObservationPublicationTarget(
      req,
      body,
      user.id,
      publicationTargetRepository(client),
    );
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
