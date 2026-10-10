import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { requireAuth } from "../_shared/auth.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { quotaIpHash } from "../_shared/aiQuota.ts";
import { runVideoRequest } from "./db.ts";
import { analyzeObservationVideo } from "./handler.ts";

export function analyzeVideoRoute(
  req: Request,
  authenticate: EdgeAuthenticator = requireAuth,
) {
  const signal = AbortSignal.any([req.signal, AbortSignal.timeout(110_000)]);
  return withEdgeHandler(req, async (user, client) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    try {
      const bounded = new Request(req, {
        body: req.body?.pipeThrough(new TransformStream(), { signal }),
        signal,
      });
      const body = await publicationAbortable(
        signal,
        () =>
          parseJsonBody(bounded, {
            limit: "standard",
            maxBytes: 1_048_576,
          }),
      );
      if (body instanceof Response) {
        return body;
      }
      return await analyzeObservationVideo(req, body, user.id, {
        run: async (owner, input) => {
          signal.throwIfAborted();
          return await runVideoRequest(
            client,
            owner,
            input,
            await quotaIpHash(req),
            signal,
          );
        },
      });
    } catch {
      return publicErrorResponse(
        req,
        503,
        "analysis_history_unavailable",
        "Identification is not available yet. Recover this analysis using its saved identity.",
      );
    }
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
