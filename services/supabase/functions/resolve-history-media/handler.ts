import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { type EvidenceIdentity } from "../_shared/analysisHistory/evidence.ts";
import {
  type CompletedMediaReceipt,
  parseResolvedMediaReceipt,
} from "../_shared/analysisHistory/initialMediaReceipt.ts";
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";

export interface CompletedMediaResolverDependencies {
  receipt(identity: EvidenceIdentity, protocol: 1 | 2 | 3): Promise<unknown>;
  sign(receipt: CompletedMediaReceipt): Promise<string>;
  now?: () => number;
}

/** Preparation ticket only: no original-media export, upload or AI execution. */
export async function resolveHistoryMedia(
  req: Request,
  body: unknown,
  owner: string,
  deps: CompletedMediaResolverDependencies,
): Promise<Response> {
  try {
    const request = exactObject(body, [
      "observation_id",
      "analysis_id",
      "media_id",
      "resolution_protocol",
    ]);
    const protocol = request.resolution_protocol;
    if (protocol !== 1 && protocol !== 2 && protocol !== 3) {
      return invalidHistory();
    }
    const identity = {
      owner_id: historyUUID(owner),
      observation_id: historyUUID(request.observation_id),
      analysis_id: historyUUID(request.analysis_id),
      media_id: historyUUID(request.media_id),
    };
    const receipt = parseResolvedMediaReceipt(
      await deps.receipt(identity, protocol),
      identity,
      protocol,
    );
    const now = deps.now ?? Date.now;
    const issued = now();
    const url = await deps.sign(receipt);
    // Ownership, immutable membership and deletion must still hold after signing.
    parseResolvedMediaReceipt(
      await deps.receipt(identity, protocol),
      identity,
      protocol,
      receipt,
    );
    if (now() >= issued + 30_000) {
      throw new HistoryError("analysis_history_unavailable");
    }
    const parsed = new URL(url);
    if (
      parsed.protocol !== "https:" || parsed.username || parsed.password ||
      parsed.hash ||
      (parsed.port && parsed.port !== "443") ||
      !/^[0-9a-f]{32}\.r2\.cloudflarestorage\.com$/.test(parsed.hostname)
    ) {
      throw new HistoryError("analysis_history_unavailable");
    }
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
      "Private media unavailable.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
