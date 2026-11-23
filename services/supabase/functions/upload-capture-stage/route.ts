import { requireAuth } from "../_shared/auth.ts";
import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  publicErrorResponse,
  readRequestBodyWithinLimit,
} from "../_shared/http.ts";
import { initialAbortable } from "../_shared/initialAnalysis/transport.ts";
import { createInitialCaptureClientServices } from "../_shared/analysisHistory/initialCaptureClientStaging.ts";
import {
  CAPTURE_STAGE_WIRE_BYTES,
  captureStageFailure,
  uploadCaptureStage,
} from "./handler.ts";

export function captureStageUploadRoute(
  req: Request,
  authenticate: EdgeAuthenticator = requireAuth,
  createServices: typeof createInitialCaptureClientServices =
    createInitialCaptureClientServices,
): Promise<Response> {
  const signal = AbortSignal.any([req.signal, AbortSignal.timeout(120_000)]);
  return withEdgeHandler(req, async (user) => {
    if (req.method !== "POST") {
      return publicErrorResponse(req, 405, "method_not_allowed", "Use POST.");
    }
    if (req.headers.get("content-type") !== "application/octet-stream") {
      return publicErrorResponse(
        req,
        415,
        "unsupported_media_type",
        "Use application/octet-stream.",
      );
    }
    try {
      signal.throwIfAborted();
      const bounded = new Request(req, {
        body: req.body?.pipeThrough(new TransformStream(), { signal }),
        signal,
      });
      const body = await initialAbortable(
        signal,
        () => readRequestBodyWithinLimit(bounded, CAPTURE_STAGE_WIRE_BYTES),
      );
      if (body.error) {
        return publicErrorResponse(
          req,
          body.error.status,
          body.error.code,
          body.error.message,
        );
      }
      if (!body.bytes) throw new Error("missing_body");
      signal.throwIfAborted();
      return await uploadCaptureStage(
        req,
        body.bytes,
        user.id,
        createServices,
        signal,
      );
    } catch (error) {
      return captureStageFailure(req, error);
    }
  }, {
    authenticate: async (request, client) => {
      try {
        return await initialAbortable(
          signal,
          () => authenticate(request, client),
        );
      } catch (error) {
        return { user: null, response: captureStageFailure(req, error) };
      }
    },
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
