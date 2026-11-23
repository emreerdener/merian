import { requireAuth } from "../_shared/auth.ts";
import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  publicErrorResponse,
  readRequestBodyWithinLimit,
} from "../_shared/http.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import {
  createInitialEvidenceUploadDependencies,
  type InitialEvidenceUploadDependencies,
} from "../_shared/analysisHistory/initialEvidenceUpload.ts";
import {
  INITIAL_UPLOAD_WIRE_MAX_BYTES,
  initialUploadFailure,
  uploadInitialEvidence,
} from "./handler.ts";

export function initialEvidenceUploadRoute(
  req: Request,
  authenticate: EdgeAuthenticator = requireAuth,
  createDependencies: () => InitialEvidenceUploadDependencies =
    createInitialEvidenceUploadDependencies,
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
      const body = await publicationAbortable(
        signal,
        () =>
          readRequestBodyWithinLimit(
            bounded,
            INITIAL_UPLOAD_WIRE_MAX_BYTES,
          ),
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
      return await uploadInitialEvidence(
        req,
        body.bytes,
        user.id,
        createDependencies(),
        signal,
      );
    } catch (error) {
      return initialUploadFailure(req, error);
    }
  }, {
    authenticate: async (request, client) => {
      try {
        return await publicationAbortable(
          signal,
          () => authenticate(request, client),
        );
      } catch (error) {
        return { user: null, response: initialUploadFailure(req, error) };
      }
    },
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
