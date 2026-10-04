import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { PublicHistoryPhotoStorage } from "../_shared/analysisHistory/publicPhotoStorage.ts";
import { publicationPhotoErasureRepository } from "./db.ts";
import { erasePublicationPhoto } from "./handler.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
  }
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return publicErrorResponse(req, 401, "unauthorized", "Unauthorized.");
  }
  try {
    const client = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const storage = new PublicHistoryPhotoStorage();
    // HTTP callers cannot nominate a key. The SQL registry chooses one due
    // obligation; an internal copy owner may use the targeted repository API.
    const result = await erasePublicationPhoto({
      ...publicationPhotoErasureRepository(client),
      erase: (object) => storage.erase(object),
    });
    return jsonResponse(result, 200, { "Cache-Control": "no-store" });
  } catch {
    return publicErrorResponse(
      req,
      503,
      "publication_photo_erasure_unavailable",
      "Photo cleanup is unavailable.",
    );
  }
});
