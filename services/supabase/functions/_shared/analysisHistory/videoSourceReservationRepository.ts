import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError, historyUUID } from "./contract.ts";
import {
  buildVideoSourceRecoveryRequest,
  decodeVideoSourceReservationReceipt,
  parseVideoSourceReservationRequest,
  VIDEO_SOURCE_READER,
} from "./videoSourceReservation.ts";

/** Reader12 service-only observations, no inference admission or dispatch.
 * Injected client must bound raw responses to2KiB and requests to5seconds.
 * Ownership authentication belongs to the caller; failures never prove vacancy.
 */
export function videoSourceReservationRepository(client: SupabaseClient) {
  async function call<T>(
    routine:
      | "reserve_owned_observation_video_source"
      | "get_owned_observation_video_source",
    owner: string,
    request: unknown,
    signal: AbortSignal,
    decode: (bytes: Uint8Array) => Promise<T>,
  ): Promise<T> {
    let onAbort = () => {};
    try {
      signal.throwIfAborted();
      const result = client.rpc(routine, {
        p_owner: owner,
        p_request: request,
        p_reader: VIDEO_SOURCE_READER,
      }).abortSignal(signal);
      const aborted = new Promise<never>((_, reject) => {
        onAbort = () =>
          reject(new HistoryError("analysis_history_unavailable"));
        signal.addEventListener("abort", onAbort, { once: true });
        if (signal.aborted) onAbort();
      });
      // A transport that delays cancellation cannot hold this owner forever.
      // Late answers cannot become another call or fabricated terminal proof.
      const decoded = Promise.resolve(result).then(async ({ data, error }) => {
        if (error) {
          throw new HistoryError(
            error.message === "analysis_history_operation_conflict"
              ? "analysis_history_operation_conflict"
              : "analysis_history_unavailable",
          );
        }
        signal.throwIfAborted();
        return await decode(new TextEncoder().encode(JSON.stringify(data)));
      });
      const receipt = await Promise.race([decoded, aborted]);
      signal.throwIfAborted();
      return receipt;
    } catch (error) {
      // A definite conflict is still not proof of vacancy or release.
      if (
        error instanceof HistoryError &&
        error.code === "analysis_history_operation_conflict"
      ) throw error;
      // All other upstream errors conceal scope and preserve uncertainty.
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
      const request = await parseVideoSourceReservationRequest(candidate);
      return call(
        "reserve_owned_observation_video_source",
        ownerID,
        request,
        signal,
        (bytes) => decodeVideoSourceReservationReceipt(bytes, request, ownerID),
      );
    },
    async recover(owner: string, candidate: unknown, caller: AbortSignal) {
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      signal.throwIfAborted();
      const ownerID = historyUUID(owner);
      const original = await parseVideoSourceReservationRequest(candidate);
      const request = await buildVideoSourceRecoveryRequest(original);
      return call(
        "get_owned_observation_video_source",
        ownerID,
        request,
        signal,
        (bytes) =>
          decodeVideoSourceReservationReceipt(bytes, original, ownerID),
      );
    },
  };
}
