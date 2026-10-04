import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { quotaIpHash } from "../_shared/aiQuota.ts";
import {
  historyWorkerRPC,
  runOwnedAnalysis,
} from "../_shared/analysisHistory/production.ts";
import { analyzeObservation } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    const body = await parseJsonBody(req, {
      limit: "standard",
      maxBytes: 1_048_576,
    });
    if (body instanceof Response) {
      return body;
    }
    return await analyzeObservation(req, body, user.id, {
      run: async (owner, input) => {
        const work = await historyWorkerRPC(
          client,
          "begin_owned_observation_analysis",
          { p_owner: owner, p_input: input, p_ip_hash: await quotaIpHash(req) },
        );
        return await runOwnedAnalysis(
          client,
          owner,
          input.observation_id as string,
          input.analysis_id as string,
          work,
        );
      },
    });
  })
);
