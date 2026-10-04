import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  type EvidenceIdentity,
  type EvidenceReceipt,
  parseEvidenceReceipt,
} from "../_shared/analysisHistory/evidence.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export interface PhotoResolverDependencies {
  receipt(identity: EvidenceIdentity): Promise<unknown>;
  sign(receipt: EvidenceReceipt): Promise<string>;
}

export async function resolveHistoryPhoto(
  req: Request,
  body: unknown,
  ownerID: string,
  deps: PhotoResolverDependencies,
): Promise<Response> {
  try {
    const request = exactObject(body, [
      "observation_id",
      "analysis_id",
      "media_id",
      "reader_protocol",
    ]);
    if (request.reader_protocol !== 8) return invalidHistory();
    const identity = {
      owner_id: historyUUID(ownerID),
      observation_id: historyUUID(request.observation_id),
      analysis_id: historyUUID(request.analysis_id),
      media_id: historyUUID(request.media_id),
    };
    const receipt = parseEvidenceReceipt(
      await deps.receipt(identity),
      identity,
    );
    if (
      receipt.ready_at === null ||
      !["image/jpeg", "image/png", "image/heic"].includes(receipt.content_type)
    ) return invalidHistory();
    const issued = Date.now();
    const url = await deps.sign(receipt);
    // Signing can suspend. Recheck deletion/account fencing before delivery.
    const current = parseEvidenceReceipt(
      await deps.receipt(identity),
      identity,
      receipt,
    );
    if (
      current.object_id !== receipt.object_id || current.ready_at === null ||
      Date.now() >= issued + 30_000
    ) {
      throw new HistoryError("analysis_history_not_found");
    }
    const parsed = new URL(url);
    if (
      parsed.protocol !== "https:" || parsed.username || parsed.password ||
      parsed.hash
    ) return invalidHistory();
    return jsonResponse(
      {
        schema_version: 1,
        ...identity,
        content_type: receipt.content_type,
        byte_count: receipt.byte_count,
        sha256: receipt.sha256,
        url,
        expires_at_ms: issued + 30_000,
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    const code = error instanceof HistoryError
      ? error.code
      : "analysis_history_unavailable";
    return publicErrorResponse(
      req,
      code === "invalid_analysis_history"
        ? 400
        : code === "analysis_history_not_found"
        ? 404
        : 503,
      code,
      "Private photo unavailable.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
