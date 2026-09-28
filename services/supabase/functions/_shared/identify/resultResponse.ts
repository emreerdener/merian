import { jsonResponse, publicErrorResponse } from "../http.ts";
import type { CompletedIdentifyResponse } from "./completedResponse.ts";
import type { IdentifySuccessEnvelope } from "./contract.ts";

/** Gate the current reader, independently of the original attempt's capability. */
export function identifyResultResponse(
  req: Request,
  envelope: IdentifySuccessEnvelope,
  headers: Record<string, string> = {},
  // Only the service-authenticated internal worker may bypass client decoding.
  internalReplay = false,
): Response {
  if (
    envelope.data.identification_provenance?.version === 2 &&
    req.headers.get("X-Merian-Identification-Protocol") !== "4" &&
    !internalReplay
  ) {
    return publicErrorResponse(
      req,
      426,
      "client_update_required",
      "Update Naturebook to read this identification.",
    );
  }
  return jsonResponse(envelope, 200, headers);
}

export function completedIdentifyResponse(
  req: Request,
  replay: CompletedIdentifyResponse,
  internalReplay = false,
): Response {
  return identifyResultResponse(req, replay.envelope, {
    "X-Merian-Idempotent-Replay": replay.source,
  }, internalReplay);
}
