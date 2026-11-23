import { runOwnedCompositionAnalysis } from "../_shared/analysisHistory/compositionProduction.ts";
import { serveGeminiEdge } from "../_shared/ai/geminiDeployment.ts";
import { withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { quotaIpHash } from "../_shared/aiQuota.ts";
import {
  historyWorkerRPC,
  runOwnedAnalysis,
} from "../_shared/analysisHistory/production.ts";
import { analyzeObservation } from "./handler.ts";

serveGeminiEdge(
  "analyze-observation",
  (req: Request) =>
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
          const composition = input.schema_version === 5 ||
            input.schema_version === 6;
          const signal = composition
            ? AbortSignal.any([req.signal, AbortSignal.timeout(110_000)])
            : undefined;
          const work = await historyWorkerRPC(
            client,
            composition
              ? "begin_owned_observation_composition_analysis"
              : "begin_owned_observation_analysis",
            {
              p_owner: owner,
              p_input: input,
              p_ip_hash: await quotaIpHash(req),
            },
            signal,
          );
          if (composition) {
            return await runOwnedCompositionAnalysis(
              client,
              owner,
              input.observation_id as string,
              input.analysis_id as string,
              work,
              signal,
            );
          }
          return await runOwnedAnalysis(
            client,
            owner,
            input.observation_id as string,
            input.analysis_id as string,
            work,
          );
        },
      });
    }),
);
