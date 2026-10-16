import type { SupabaseClient } from "@supabase/supabase-js";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../serviceRoleClient.ts";
import { HistoryError, historyUUID, invalidHistory } from "./contract.ts";
import {
  buildVideoEvidenceUploadRequest,
  decodeVideoEvidenceReceipt,
  VIDEO_EVIDENCE_READER,
  VIDEO_EVIDENCE_RECEIPT_MAX_BYTES,
  type VideoEvidenceReceipt,
} from "./videoEvidence.ts";
import { parseVideoSourceReservationRequest } from "./videoSourceReservation.ts";

/** Prepared service-only adapter. Construct the injected client through the
 * service-role factory with requestTimeoutMs:5000 and maximumResponseBytes:8192.
 * Caller owns authentication and byte verification; this grants neither.
 */
export function videoEvidenceRepository(client: SupabaseClient) {
  async function call(
    routine:
      | "reserve_owned_observation_video_evidence"
      | "complete_owned_observation_video_evidence",
    args: Record<string, unknown>,
    signal: AbortSignal,
    decode: (bytes: Uint8Array) => Promise<VideoEvidenceReceipt>,
  ) {
    let onAbort = () => {};
    try {
      signal.throwIfAborted();
      const response = client.rpc(routine, args).abortSignal(signal);
      const aborted = new Promise<never>((_, reject) => {
        onAbort = () =>
          reject(new HistoryError("analysis_history_unavailable"));
        signal.addEventListener("abort", onAbort, { once: true });
        if (signal.aborted) onAbort();
      });
      const decoded = Promise.resolve(response).then(
        async ({ data, error }) => {
          if (error) {
            throw new HistoryError(
              error.message === "analysis_history_operation_conflict"
                ? "analysis_history_operation_conflict"
                : "analysis_history_unavailable",
            );
          }
          signal.throwIfAborted();
          return await decode(new TextEncoder().encode(JSON.stringify(data)));
        },
      );
      const result = await Promise.race([decoded, aborted]);
      signal.throwIfAborted();
      return result;
    } catch (error) {
      if (
        error instanceof HistoryError &&
        error.code === "analysis_history_operation_conflict"
      ) throw error;
      throw new HistoryError("analysis_history_unavailable");
    } finally {
      signal.removeEventListener("abort", onAbort);
    }
  }
  return {
    async reserve(owner: string, candidate: unknown, caller: AbortSignal) {
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      signal.throwIfAborted();
      const ownerID = historyUUID(owner);
      const original = await parseVideoSourceReservationRequest(candidate);
      const request = await buildVideoEvidenceUploadRequest(original);
      return call(
        "reserve_owned_observation_video_evidence",
        {
          p_owner: ownerID,
          p_request: request,
          p_reader: VIDEO_EVIDENCE_READER,
        },
        signal,
        (bytes) => decodeVideoEvidenceReceipt(bytes, original, ownerID),
      );
    },
    /** Only call after trusted verification of this exact allocated object's bytes. */
    async complete(
      owner: string,
      candidate: unknown,
      prior: Uint8Array,
      mediaID: string,
      caller: AbortSignal,
    ) {
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      signal.throwIfAborted();
      const ownerID = historyUUID(owner), media = historyUUID(mediaID);
      // Bound before copying and own the original bytes across candidate hashing.
      if (
        prior.byteLength === 0 ||
        prior.byteLength > VIDEO_EVIDENCE_RECEIPT_MAX_BYTES
      ) {
        return invalidHistory();
      }
      const saved = prior.slice();
      const original = await parseVideoSourceReservationRequest(candidate);
      const receipt = await decodeVideoEvidenceReceipt(
        saved,
        original,
        ownerID,
      );
      const item = receipt.items.find((item) => item.media_id === media);
      if (!item) return invalidHistory();
      const request = await buildVideoEvidenceUploadRequest(original);
      return call(
        "complete_owned_observation_video_evidence",
        {
          p_owner: ownerID,
          p_request: request,
          p_media: media,
          p_object: item.object_id,
          p_reader: VIDEO_EVIDENCE_READER,
        },
        signal,
        async (bytes) => {
          const result = await decodeVideoEvidenceReceipt(
            bytes,
            original,
            ownerID,
            saved,
          );
          if (
            result.items.find((item) => item.media_id === media)?.ready_at ==
              null
          ) return invalidHistory();
          return result;
        },
      );
    },
  };
}

/** Bounded live factory; construction makes no RPC. Video ingress installs it. */
export function createVideoEvidenceRepository() {
  return videoEvidenceRepository(
    createServiceRoleClientFromEnvironmentWithOptions({
      requestTimeoutMs: 5_000,
      maximumResponseBytes: VIDEO_EVIDENCE_RECEIPT_MAX_BYTES,
    }),
  );
}
