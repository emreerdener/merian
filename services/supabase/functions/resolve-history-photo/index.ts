import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { PrivateHistoryEvidenceStorage } from "../_shared/analysisHistory/evidenceStorage.ts";
import { resolvePhotoReceipt } from "./db.ts";
import { resolveHistoryPhoto } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) {
      return body;
    }
    const storage = new PrivateHistoryEvidenceStorage();
    return await resolveHistoryPhoto(req, body, user.id, {
      receipt: (identity) => resolvePhotoReceipt(client, identity),
      sign: (receipt) => storage.signedRead(receipt),
    });
  })
);
