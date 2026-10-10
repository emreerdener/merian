import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { exactObject } from "../_shared/analysisHistory/contract.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { recoverVideoAnalyses } from "./db.ts";

export async function recoverVideoRoute(req: Request) {
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
    const signal = AbortSignal.any([req.signal, AbortSignal.timeout(5_000)]);
    const bounded = new Request(req, {
      body: req.body?.pipeThrough(new TransformStream(), { signal }),
      signal,
    });
    const body = await publicationAbortable(
      signal,
      () =>
        parseJsonBody(bounded, {
          limit: "standard",
          maxBytes: 1024,
        }),
    );
    if (body instanceof Response) return body;
    exactObject(body, []);
    const client = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const counts = await recoverVideoAnalyses(client);
    return jsonResponse(counts, 200, { "Cache-Control": "no-store" });
  } catch {
    return publicErrorResponse(
      req,
      503,
      "analysis_history_unavailable",
      "Recovery is unavailable.",
    );
  }
}
