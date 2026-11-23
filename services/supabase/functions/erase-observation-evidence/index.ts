import { serveEdge } from "../_shared/edgeHandler.ts";
import { corsHeaders, publicErrorResponse } from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { PrivateEvidenceErasureStorage } from "./storage.ts";
import { evidenceErasureRepository } from "./db.ts";
import { eraseObservationEvidence } from "./handler.ts";
import { evidenceWorkerReceipt } from "./receipt.ts";

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
    return await evidenceWorkerReceipt(req, async (dispatch) => {
      const client = createServiceRoleClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        auth.serverApiKey,
      );
      const storage = new PrivateEvidenceErasureStorage();
      // No caller body or key is consumed. Only the gated registry grants erasure.
      const counts = await eraseObservationEvidence({
        ...evidenceErasureRepository(client, dispatch),
        erase: (object, signal, target) =>
          storage.erase(object, signal, target),
      }, req.signal);
      return counts;
    });
  } catch {
    return publicErrorResponse(
      req,
      503,
      "private_evidence_erasure_unavailable",
      "Private media cleanup is unavailable.",
      { extraHeaders: headers },
    );
  }
});
