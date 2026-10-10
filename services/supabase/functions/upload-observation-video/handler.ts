import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { VIDEO_EVIDENCE_READER } from "../_shared/analysisHistory/videoEvidence.ts";
import { VIDEO_SOURCE_MAX_REQUEST_BYTES } from "../_shared/analysisHistory/videoSourceReservation.ts";
import {
  uploadVideoEvidenceItem,
  type VideoUploadDependencies,
} from "../_shared/analysisHistory/videoUpload.ts";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const VIDEO_UPLOAD_METADATA_MAX_BYTES = VIDEO_SOURCE_MAX_REQUEST_BYTES +
  256;
export const VIDEO_UPLOAD_WIRE_MAX_BYTES = 4 + VIDEO_UPLOAD_METADATA_MAX_BYTES +
  MEDIA_BUDGETS.maxVideoRawBytes;
export function videoUploadFailure(req: Request, error: unknown): Response {
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
    "Private video upload is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}

/** Wire1: big-endian metadata length, closed UTF-8 JSON, then one exact item. */
export async function uploadObservationVideo(
  req: Request,
  body: Uint8Array,
  owner: string,
  dependencies: VideoUploadDependencies,
  signal: AbortSignal,
): Promise<Response> {
  try {
    signal.throwIfAborted();
    if (body.length < 5 || body.length > VIDEO_UPLOAD_WIRE_MAX_BYTES) {
      return invalidHistory();
    }
    const length = new DataView(body.buffer, body.byteOffset, body.byteLength)
      .getUint32(0);
    if (
      length < 1 || length > VIDEO_UPLOAD_METADATA_MAX_BYTES ||
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
    if (
      row.schema_version !== 1 || row.reader_version !== VIDEO_EVIDENCE_READER
    ) return invalidHistory();
    const media = historyUUID(row.media_id);
    const receipt = await uploadVideoEvidenceItem(
      row.candidate,
      owner,
      media,
      body.subarray(4 + length),
      dependencies,
      signal,
    );
    signal.throwIfAborted();
    return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
  } catch (error) {
    return videoUploadFailure(req, error);
  }
}
