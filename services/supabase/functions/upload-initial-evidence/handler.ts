import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { INITIAL_ORIGINAL_MAX_BYTES } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  type InitialEvidenceUploadDependencies,
  uploadInitialEvidenceArtifact,
} from "../_shared/analysisHistory/initialEvidenceUpload.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const INITIAL_UPLOAD_METADATA_MAX_BYTES = 1_044_480 + 256;
export const INITIAL_UPLOAD_WIRE_MAX_BYTES = 4 +
  INITIAL_UPLOAD_METADATA_MAX_BYTES + INITIAL_ORIGINAL_MAX_BYTES;

export function initialUploadFailure(req: Request, error: unknown): Response {
  const code = error instanceof HistoryError
    ? error.code
    : "analysis_history_unavailable";
  return publicErrorResponse(
    req,
    code === "invalid_analysis_history"
      ? 400
      : code === "analysis_history_operation_conflict"
      ? 409
      : 503,
    code,
    "Private media upload is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}

/** Wire1: four-byte big-endian metadata length, closed UTF-8 JSON, then one
 * exact artifact. No object key, URL, role override or owner comes from clients.
 */
export async function uploadInitialEvidence(
  req: Request,
  body: Uint8Array,
  owner: string,
  dependencies: InitialEvidenceUploadDependencies,
  signal: AbortSignal,
): Promise<Response> {
  try {
    signal.throwIfAborted();
    if (body.length < 5 || body.length > INITIAL_UPLOAD_WIRE_MAX_BYTES) {
      return invalidHistory();
    }
    const length = new DataView(body.buffer, body.byteOffset, body.byteLength)
      .getUint32(0);
    if (
      length < 1 || length > INITIAL_UPLOAD_METADATA_MAX_BYTES ||
      4 + length >= body.length
    ) return invalidHistory();
    let metadata: unknown;
    try {
      metadata = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(
          body.subarray(4, 4 + length),
        ),
      );
    } catch {
      return invalidHistory();
    }
    const row = exactObject(metadata, [
      "schema_version",
      "request",
      "media_id",
    ]);
    if (row.schema_version !== 1) return invalidHistory();
    const result = await uploadInitialEvidenceArtifact(
      owner,
      row.request,
      historyUUID(row.media_id),
      body.subarray(4 + length),
      dependencies,
      signal,
    );
    signal.throwIfAborted();
    return jsonResponse(result, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    return initialUploadFailure(req, error);
  }
}
