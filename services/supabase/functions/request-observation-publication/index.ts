import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { quotaIpHash } from "../_shared/aiQuota.ts";
import { publicationOperationRepository } from "./db.ts";
import { requestObservationPublication } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small", maxBytes: 4096 });
    if (body instanceof Response) {
      return body;
    }
    return await requestObservationPublication(req, body, user.id, {
      admit: async (owner, input) =>
        publicationOperationRepository(client).admit(
          owner,
          input,
          await quotaIpHash(req),
        ),
    });
  })
);
