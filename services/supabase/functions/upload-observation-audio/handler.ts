import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  evidenceDigest,
  type EvidenceIdentity,
  type EvidenceReceipt,
  type EvidenceUpload,
  parseAudioEvidenceReceipt,
} from "../_shared/analysisHistory/evidence.ts";
import { validatePreparedAudioContainer } from "../_shared/analysisHistory/audioContainer.ts";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const UPLOAD_WIRE_MAX_BYTES = MEDIA_BUDGETS.maxAudioRawBytes + 1024 + 4;
export interface AudioUploadDependencies {
  reserve(input: EvidenceUpload, signal: AbortSignal): Promise<unknown>;
  write(
    receipt: EvidenceReceipt,
    bytes: Uint8Array,
    signal: AbortSignal,
  ): Promise<void>;
  complete(
    identity: EvidenceIdentity,
    object: string,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export function uploadFailure(req: Request, error: unknown): Response {
  const code = error instanceof HistoryError
    ? error.code
    : "analysis_history_unavailable";
  return publicErrorResponse(
    req,
    code === "invalid_analysis_history"
      ? 400
      : code === "analysis_history_not_found"
      ? 404
      : code === "analysis_history_operation_conflict"
      ? 409
      : 503,
    code,
    "Private audio upload is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}
export async function uploadObservationAudio(
  req: Request,
  body: Uint8Array,
  owner: string,
  deps: AudioUploadDependencies,
  signal: AbortSignal,
): Promise<Response> {
  try {
    signal.throwIfAborted();
    if (body.length < 5 || body.length > UPLOAD_WIRE_MAX_BYTES) {
      invalidHistory();
    }
    const length = new DataView(body.buffer, body.byteOffset, body.byteLength)
      .getUint32(0);
    if (length < 1 || length > 1024 || 4 + length >= body.length) {
      invalidHistory();
    }
    let metadata: unknown;
    try {
      metadata = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(
          body.subarray(4, 4 + length),
        ),
      );
    } catch {
      return uploadFailure(req, new HistoryError("invalid_analysis_history"));
    }
    const row = exactObject(metadata, [
      "schema_version",
      "observation_id",
      "analysis_id",
      "audio",
    ]);
    const item = exactObject(row.audio, [
      "media_id",
      "content_type",
      "byte_count",
    ]);
    const identity = {
      owner_id: historyUUID(owner),
      observation_id: historyUUID(row.observation_id),
      analysis_id: historyUUID(row.analysis_id),
      media_id: historyUUID(item.media_id),
    };
    if (
      row.schema_version !== 1 ||
      new Set([
          identity.observation_id,
          identity.analysis_id,
          identity.media_id,
        ]).size !== 3 ||
      item.content_type !== "audio/wav" ||
      !Number.isSafeInteger(item.byte_count) ||
      item.byte_count !== body.length - 4 - length
    ) invalidHistory();
    // Own and validate every input byte before any asynchronous admission.
    const bytes = body.slice(4 + length);
    validatePreparedAudioContainer(bytes);
    const input: EvidenceUpload = {
      ...identity,
      content_type: "audio/wav",
      byte_count: bytes.length,
      sha256: await evidenceDigest(bytes),
    };
    signal.throwIfAborted();
    const receipt = parseAudioEvidenceReceipt(
      await publicationAbortable(signal, () => deps.reserve(input, signal)),
      identity,
      input,
    );
    signal.throwIfAborted();
    if (Date.parse(receipt.expires_at) <= Date.now()) {
      throw new Error("expired_receipt");
    }
    if (receipt.ready_at === null) {
      // Stop storage before the final bounded completion-attempt window.
      // SQL expiry still wins; accepted bytes may need independent erasure.
      const writeUntil = Date.parse(receipt.expires_at) - 12_000;
      const remaining = writeUntil - Date.now();
      if (remaining <= 0) throw new Error("insufficient_receipt_budget");
      const deadline = new AbortController();
      const writeSignal = AbortSignal.any([signal, deadline.signal]);
      const timer = setTimeout(() => deadline.abort(), remaining);
      try {
        await publicationAbortable(
          writeSignal,
          () => deps.write(receipt, bytes, writeSignal),
        );
        writeSignal.throwIfAborted();
        if (Date.now() >= writeUntil) throw new Error("expired_write_budget");
      } finally {
        clearTimeout(timer);
      }
    }
    signal.throwIfAborted();
    // Ready replay still rechecks owner/deletion and the original fixed expiry.
    const completed = parseAudioEvidenceReceipt(
      await publicationAbortable(
        signal,
        () => deps.complete(identity, receipt.object_id, signal),
      ),
      identity,
      input,
    );
    if (
      completed.object_id !== receipt.object_id ||
      completed.expires_at !== receipt.expires_at ||
      completed.ready_at === null ||
      (receipt.ready_at !== null && completed.ready_at !== receipt.ready_at)
    ) throw new Error("invalid_completion");
    signal.throwIfAborted();
    return jsonResponse(
      {
        schema_version: 1,
        observation_id: identity.observation_id,
        analysis_id: identity.analysis_id,
        items: [{
          kind: "audio",
          media_id: identity.media_id,
          content_type: input.content_type,
          byte_count: input.byte_count,
          sha256: input.sha256,
        }],
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    return uploadFailure(req, error);
  }
}
