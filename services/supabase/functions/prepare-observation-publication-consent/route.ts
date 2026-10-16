import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { publicationConsentRepository } from "./db.ts";
import { prepareObservationPublicationConsent } from "./handler.ts";

export function publicationConsentRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small", maxBytes: 1024 });
    if (body instanceof Response) return body;
    return prepareObservationPublicationConsent(
      req,
      body,
      user.id,
      publicationConsentRepository(client),
    );
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
