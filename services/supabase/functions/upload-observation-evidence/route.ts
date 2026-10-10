import {
  type EdgeAuthenticator,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  publicErrorResponse,
  readRequestBodyWithinLimit,
} from "../_shared/http.ts";
import { PrivateHistoryEvidenceStorage } from "../_shared/analysisHistory/evidenceStorage.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { evidenceUploadRepository } from "./db.ts";
import {
  UPLOAD_WIRE_MAX_BYTES,
  uploadFailure,
  uploadObservationEvidence,
} from "./handler.ts";
export function evidenceUploadRoute(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  // Includes authentication/body ingestion, every RPC and all sequential writes.
  const signal = AbortSignal.any([req.signal, AbortSignal.timeout(120_000)]);
  return withEdgeHandler(req, async (user, client) => {
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
      const bounded = new Request(req, {
        body: req.body?.pipeThrough(new TransformStream(), { signal }),
        signal,
      });
      const body = await publicationAbortable(
        signal,
        () => readRequestBodyWithinLimit(bounded, UPLOAD_WIRE_MAX_BYTES),
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
      const storage = new PrivateHistoryEvidenceStorage();
      return await uploadObservationEvidence(req, body.bytes, user.id, {
        ...evidenceUploadRepository(client),
        write: (receipt, bytes, parent) =>
          storage.writeOnce(receipt, bytes, parent),
      }, signal);
    } catch (error) {
      return uploadFailure(req, error);
    }
  }, {
    authenticate,
    responseHeaders: { "Cache-Control": "private, no-store" },
  });
}
