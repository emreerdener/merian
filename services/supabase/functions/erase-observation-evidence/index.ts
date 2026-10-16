import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { PrivateHistoryEvidenceStorage } from "../_shared/analysisHistory/evidenceStorage.ts";
import { evidenceErasureRepository } from "./db.ts";
import { eraseObservationEvidence } from "./handler.ts";

serveEdge(async (req: Request) => {
  const headers = { "Cache-Control": "no-store" };
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { ...corsHeaders, ...headers } });
  }
  if (req.method !== "POST") {
    return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.", {
      extraHeaders: headers,
    });
  }
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return publicErrorResponse(req, 401, "unauthorized", "Unauthorized.", {
      extraHeaders: headers,
    });
  }
  try {
    const client = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const storage = new PrivateHistoryEvidenceStorage();
    // No caller body or key is consumed. Only the gated registry grants erasure.
    const counts = await eraseObservationEvidence({
      ...evidenceErasureRepository(client),
      erase: (object, signal) => storage.erase(object, signal),
    }, req.signal);
    return jsonResponse(counts, 200, headers);
  } catch {
    return publicErrorResponse(
      req,
      503,
      "private_evidence_erasure_unavailable",
      "Photo cleanup is unavailable.",
      { extraHeaders: headers },
    );
  }
});
