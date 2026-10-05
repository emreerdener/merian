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
  parseEvidenceReceipt,
} from "../_shared/analysisHistory/evidence.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export const UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
export const UPLOAD_WIRE_MAX_BYTES = UPLOAD_MAX_BYTES + 4096 + 4;
export interface UploadDescriptor {
  media_id: string;
  content_type: string;
  byte_count: number;
  sha256: string;
}
export interface UploadCohort {
  owner_id: string;
  observation_id: string;
  analysis_id: string;
  items: UploadDescriptor[];
}
export interface UploadDependencies {
  reserve(input: UploadCohort, signal: AbortSignal): Promise<unknown>;
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
    "Private evidence upload is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}
export async function uploadObservationEvidence(
  req: Request,
  body: Uint8Array,
  owner: string,
  deps: UploadDependencies,
  signal: AbortSignal,
): Promise<Response> {
  try {
    if (body.byteLength < 5 || body.byteLength > UPLOAD_WIRE_MAX_BYTES) {
      invalidHistory();
    }
    const metadataLength = new DataView(
      body.buffer,
      body.byteOffset,
      body.byteLength,
    ).getUint32(0);
    if (
      metadataLength < 1 || metadataLength > 4096 ||
      metadataLength + 4 >= body.byteLength
    ) invalidHistory();
    let metadata: unknown;
    try {
      metadata = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(
          body.subarray(4, 4 + metadataLength),
        ),
      );
    } catch {
      return uploadFailure(req, new HistoryError("invalid_analysis_history"));
    }
    let offset = 4 + metadataLength;
    const row = exactObject(metadata, [
      "schema_version",
      "observation_id",
      "analysis_id",
      "photos",
    ]);
    if (
      row.schema_version !== 1 || !Array.isArray(row.photos) ||
      row.photos.length < 1 || row.photos.length > 5
    ) invalidHistory();
    const input: UploadCohort = {
      owner_id: historyUUID(owner),
      observation_id: historyUUID(row.observation_id),
      analysis_id: historyUUID(row.analysis_id),
      items: [],
    };
    if (input.observation_id === input.analysis_id) invalidHistory();
    const buffers: Uint8Array[] = [];
    const seen = new Set<string>();
    let total = 0;
    // Validate and own every byte before any reservation or object write.
    for (const photo of row.photos) {
      signal.throwIfAborted();
      const item = exactObject(photo, [
        "media_id",
        "content_type",
        "byte_count",
      ]);
      const media = historyUUID(item.media_id);
      if (
        seen.has(media) ||
        [input.observation_id, input.analysis_id].includes(media) ||
        typeof item.content_type !== "string" ||
        !["image/jpeg", "image/png"].includes(item.content_type) ||
        typeof item.byte_count !== "number" ||
        !Number.isSafeInteger(item.byte_count) ||
        item.byte_count < 1 || item.byte_count > UPLOAD_MAX_BYTES
      ) invalidHistory();
      total += item.byte_count;
      if (
        total > UPLOAD_MAX_BYTES || offset + item.byte_count > body.byteLength
      ) invalidHistory();
      const bytes = body.slice(offset, offset + item.byte_count);
      offset += item.byte_count;
      seen.add(media);
      buffers.push(bytes);
      input.items.push({
        media_id: media,
        content_type: item.content_type,
        byte_count: bytes.byteLength,
        sha256: await evidenceDigest(bytes),
      });
    }
    if (offset !== body.byteLength) invalidHistory();
    const reserved = await publicationAbortable(
      signal,
      () => deps.reserve(input, signal),
    );
    if (!Array.isArray(reserved) || reserved.length !== input.items.length) {
      throw new Error("invalid_receipts");
    }
    // Verify the entire returned cohort before the first external object write.
    const receipts = input.items.map((item, index) =>
      parseEvidenceReceipt(reserved[index], {
        ...input,
        media_id: item.media_id,
      }, { ...input, ...item })
    );
    if (
      new Set(receipts.map((r) => r.object_id)).size !== receipts.length ||
      new Set(receipts.map((r) => r.expires_at)).size !== 1
    ) throw new Error("invalid_receipts");
    for (const [index, receipt] of receipts.entries()) {
      signal.throwIfAborted();
      if (receipt.ready_at === null) {
        if (Date.parse(receipt.expires_at) <= Date.now()) {
          throw new Error("expired_receipt");
        }
        await publicationAbortable(
          signal,
          () => deps.write(receipt, buffers[index], signal),
        );
      }
      // Revalidate ownership/deletion even when reservation recovered ready bytes.
      const complete = parseEvidenceReceipt(
        await publicationAbortable(
          signal,
          () => deps.complete(receipt, receipt.object_id, signal),
        ),
        receipt,
        receipt,
      );
      if (
        complete.object_id !== receipt.object_id ||
        complete.expires_at !== receipt.expires_at || complete.ready_at === null
      ) throw new Error("invalid_completion");
    }
    return jsonResponse(
      {
        schema_version: 1,
        observation_id: input.observation_id,
        analysis_id: input.analysis_id,
        items: input.items.map((item) => ({ kind: "image", ...item })),
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    return uploadFailure(req, error);
  }
}
