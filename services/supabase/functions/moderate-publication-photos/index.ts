import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { publicationModerationWorkerRepository } from "./db.ts";
import { moderatePublicationPhotos } from "./handler.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.", {
      extraHeaders: { "Cache-Control": "no-store" },
    });
  }
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return publicErrorResponse(req, 401, "unauthorized", "Unauthorized.", {
      extraHeaders: { "Cache-Control": "no-store" },
    });
  }
  try {
    const client = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const counts = await moderatePublicationPhotos(
      publicationModerationWorkerRepository(client),
    );
    return jsonResponse(counts, 200, { "Cache-Control": "no-store" });
  } catch {
    return publicErrorResponse(
      req,
      503,
      "analysis_history_unavailable",
      "Moderation is unavailable.",
      { extraHeaders: { "Cache-Control": "no-store" } },
    );
  }
});
