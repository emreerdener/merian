import type { SupabaseClient } from "@supabase/supabase-js";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../serviceRoleClient.ts";
import { HistoryError, historyUUID, invalidHistory } from "./contract.ts";
import {
  COMPOSITION_RECEIPT_MAX_BYTES,
  type CompositionEvidenceReceipt,
  decodeCompositionEvidenceReceipt,
} from "./compositionEvidence.ts";
import {
  compositionSourceReaderVersion,
  parseCompositionSourceReservationRequest,
} from "./compositionSourceReservation.ts";
import { compositionEvidenceIdentity } from "./compositionEvidence.ts";
import { compositionCohortItems } from "./compositionCohort.ts";
async function buildCompositionEvidenceUploadRequest(candidate: unknown) {
  const original = await parseCompositionSourceReservationRequest(candidate);
  return {
    ...await compositionEvidenceIdentity(original.input),
    items: compositionCohortItems(original.input),
  };
}

/** Prepared service-only adapter. Construct the injected client through the
 * service-role factory with requestTimeoutMs:5000 and maximumResponseBytes:16384.
 * Caller owns authentication and byte verification; this grants neither.
 */
export function compositionEvidenceRepository(client: SupabaseClient) {
  async function call(
    routine:
      | "reserve_owned_observation_composition_evidence"
      | "complete_owned_observation_composition_evidence",
    args: Record<string, unknown>,
    signal: AbortSignal,
    decode: (bytes: Uint8Array) => Promise<CompositionEvidenceReceipt>,
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
      const original = await parseCompositionSourceReservationRequest(
        candidate,
      );
      const request = await buildCompositionEvidenceUploadRequest(original);
      return call(
        "reserve_owned_observation_composition_evidence",
        {
          p_owner: ownerID,
          p_request: request,
          p_reader: compositionSourceReaderVersion(original),
        },
        signal,
        (bytes) =>
          decodeCompositionEvidenceReceipt(bytes, original.input, ownerID),
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
        prior.byteLength > COMPOSITION_RECEIPT_MAX_BYTES
      ) {
        return invalidHistory();
      }
      const saved = prior.slice();
      const original = await parseCompositionSourceReservationRequest(
        candidate,
      );
      const receipt = await decodeCompositionEvidenceReceipt(
        saved,
        original.input,
        ownerID,
      );
      const item = receipt.items.find((item) => item.media_id === media);
      if (!item) return invalidHistory();
      const request = await buildCompositionEvidenceUploadRequest(original);
      return call(
        "complete_owned_observation_composition_evidence",
        {
          p_owner: ownerID,
          p_request: request,
          p_media: media,
          p_object: item.object_id,
          p_reader: compositionSourceReaderVersion(original),
        },
        signal,
        async (bytes) => {
          const result = await decodeCompositionEvidenceReceipt(
            bytes,
            original.input,
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

/** Bounded live factory; construction makes no RPC. Composition ingress installs it. */
export function createCompositionEvidenceRepository() {
  return compositionEvidenceRepository(
    createServiceRoleClientFromEnvironmentWithOptions({
      requestTimeoutMs: 5_000,
      maximumResponseBytes: COMPOSITION_RECEIPT_MAX_BYTES,
    }),
  );
}
