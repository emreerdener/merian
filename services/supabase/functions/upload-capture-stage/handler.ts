import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { INITIAL_ORIGINAL_MAX_BYTES } from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import {
  createInitialCaptureClientServices,
  uploadInitialCaptureClientArtifact,
} from "../_shared/analysisHistory/initialCaptureClientStaging.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const CAPTURE_STAGE_METADATA_BYTES = 1_044_480 + 256;
export const CAPTURE_STAGE_WIRE_BYTES = 4 + CAPTURE_STAGE_METADATA_BYTES +
  INITIAL_ORIGINAL_MAX_BYTES;
export function captureStageFailure(req: Request, error: unknown): Response {
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
    "Private capture upload is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}
/** Wire1 has a big-endian metadata length, closed UTF8 JSON, and one exact
 * client-known artifact. The plan contains neither owner nor private object ID. */
export async function uploadCaptureStage(
  req: Request,
  body: Uint8Array,
  owner: string,
  createServices: typeof createInitialCaptureClientServices,
  signal: AbortSignal,
): Promise<Response> {
  try {
    signal.throwIfAborted();
    if (body.length < 5 || body.length > CAPTURE_STAGE_WIRE_BYTES) {
      return invalidHistory();
    }
    const length = new DataView(body.buffer, body.byteOffset, body.byteLength)
      .getUint32(0);
    if (
      length < 1 || length > CAPTURE_STAGE_METADATA_BYTES ||
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
    const row = exactObject(metadata, ["schema_version", "plan", "media_id"]);
    if (row.schema_version !== 1) return invalidHistory();
    const result = await uploadInitialCaptureClientArtifact(
      owner,
      row.plan,
      historyUUID(row.media_id),
      body.subarray(4 + length),
      createServices,
      signal,
    );
    signal.throwIfAborted();
    return jsonResponse(result, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    return captureStageFailure(req, error);
  }
}
