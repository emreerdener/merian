import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import {
  historyWorkerRPC,
  runOwnedAnalysis,
} from "../_shared/analysisHistory/production.ts";
import { recoverObservationAnalyses } from "./handler.ts";

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
    const counts = await recoverObservationAnalyses({
      now: Date.now,
      list: () =>
        historyWorkerRPC(client, "list_observation_analysis_recovery", {}),
      recover: async (owner, observation, analysis) => {
        const work = await historyWorkerRPC(
          client,
          "claim_observation_analysis_recovery",
          { p_owner: owner, p_observation: observation, p_analysis: analysis },
        );
        if (
          !work || typeof work !== "object" || !("claimed" in work) ||
          work.claimed !== true
        ) return false;
        const state = await runOwnedAnalysis(
          client,
          owner,
          observation,
          analysis,
          work,
        );
        return state === "complete" || state === "failed_terminal";
      },
    });
    return jsonResponse(counts, 200, { "Cache-Control": "no-store" });
  } catch {
    return publicErrorResponse(
      req,
      503,
      "analysis_history_unavailable",
      "Recovery is unavailable.",
    );
  }
});
