import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError, historyUUID } from "./contract.ts";
import {
  buildSourceRetirementRequest,
  decodeSourceReservationReceipt,
  decodeSourceRetirementReceipt,
  parseSourceReservationRequest,
  SOURCE_RESERVATION_READER,
} from "./sourceReservation.ts";

/** Service-only RPC observations; no inference admission or dispatch. */
export function sourceReservationRepository(client: SupabaseClient) {
  async function call<T>(
    routine:
      | "reserve_owned_observation_analysis_source"
      | "retire_owned_observation_analysis_source",
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
        p_reader: SOURCE_RESERVATION_READER,
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
      const ownerID = historyUUID(owner);
      const request = await parseSourceReservationRequest(candidate);
      return call(
        "reserve_owned_observation_analysis_source",
        ownerID,
        request,
        signal,
        (bytes) => decodeSourceReservationReceipt(bytes, request, ownerID),
      );
    },
    async retireUnfunded(
      owner: string,
      candidate: unknown,
      operationID: string,
      caller: AbortSignal,
    ) {
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      const ownerID = historyUUID(owner);
      const original = await parseSourceReservationRequest(candidate);
      const request = await buildSourceRetirementRequest(original, operationID);
      return call(
        "retire_owned_observation_analysis_source",
        ownerID,
        request,
        signal,
        (bytes) =>
          decodeSourceRetirementReceipt(bytes, original, request, ownerID),
      );
    },
  };
}
