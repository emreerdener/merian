import { jsonResponse, publicErrorResponse } from "../http.ts";
import type { CompletedIdentifyResponse } from "./completedResponse.ts";
import {
  identificationResultContract,
  type IdentifySuccessEnvelope,
} from "./contract.ts";

/** Gate the current reader, independently of the original attempt's capability. */
export function identifyResultResponse(
  req: Request,
  envelope: IdentifySuccessEnvelope,
  headers: Record<string, string> = {},
  // Only the service-authenticated internal worker may bypass client decoding.
  internalReplay = false,
): Response {
  const protocol = req.headers.get("X-Merian-Identification-Protocol");
  const requiresPrimaryReader =
    envelope.data.primary_identification !== undefined ||
    identificationResultContract(
        envelope.data.identification_provenance?.schema,
      ) === "primary_v1";
  const supported = requiresPrimaryReader
    ? (protocol === "5" || protocol === "6")
    : envelope.data.identification_provenance?.version !== 2 ||
      protocol === "4" || (protocol === "5" || protocol === "6");
  if (!supported && !internalReplay) {
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
