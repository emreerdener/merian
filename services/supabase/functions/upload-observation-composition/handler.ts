import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  compositionSourceReaderVersion,
  parseCompositionSourceReservationRequest,
} from "../_shared/analysisHistory/compositionSourceReservation.ts";
import { COMPOSITION_SOURCE_MAX_REQUEST_BYTES } from "../_shared/analysisHistory/compositionSourceReservation.ts";
import {
  type CompositionUploadDependencies,
  uploadCompositionEvidenceItem,
} from "../_shared/analysisHistory/compositionUpload.ts";
import { EVIDENCE_MAX_BYTES } from "../_shared/analysisHistory/evidence.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const COMPOSITION_UPLOAD_METADATA_MAX_BYTES =
  COMPOSITION_SOURCE_MAX_REQUEST_BYTES +
  256;
export const COMPOSITION_UPLOAD_WIRE_MAX_BYTES = 4 +
  COMPOSITION_UPLOAD_METADATA_MAX_BYTES +
  EVIDENCE_MAX_BYTES;
export function compositionUploadFailure(
  req: Request,
  error: unknown,
): Response {
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

/** Wire1: big-endian metadata length, closed UTF-8 JSON, then one exact item. */
export async function uploadObservationComposition(
  req: Request,
  body: Uint8Array,
  owner: string,
  dependencies: CompositionUploadDependencies,
  signal: AbortSignal,
): Promise<Response> {
  try {
    signal.throwIfAborted();
    if (body.length < 5 || body.length > COMPOSITION_UPLOAD_WIRE_MAX_BYTES) {
      return invalidHistory();
    }
    const length = new DataView(body.buffer, body.byteOffset, body.byteLength)
      .getUint32(0);
    if (
      length < 1 || length > COMPOSITION_UPLOAD_METADATA_MAX_BYTES ||
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
      "reader_version",
      "candidate",
      "media_id",
    ]);
    const candidate = await parseCompositionSourceReservationRequest(
      row.candidate,
    );
    if (
      row.schema_version !== 1 ||
      row.reader_version !== compositionSourceReaderVersion(candidate)
    ) return invalidHistory();
    const media = historyUUID(row.media_id);
    const receipt = await uploadCompositionEvidenceItem(
      candidate,
      owner,
      media,
      body.subarray(4 + length),
      dependencies,
      signal,
    );
    signal.throwIfAborted();
    return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    return compositionUploadFailure(req, error);
  }
}
