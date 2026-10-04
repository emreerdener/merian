import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { publicationStatusRepository } from "./db.ts";
import { getObservationPublicationStatus } from "./handler.ts";

export function publicationStatusRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small", maxBytes: 1024 });
    if (body instanceof Response) return body;
    return getObservationPublicationStatus(
      req,
      body,
      user.id,
      publicationStatusRepository(client),
    );
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
