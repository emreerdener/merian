import type { SupabaseClient } from "@supabase/supabase-js";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../serviceRoleClient.ts";
import { HistoryError, historyUUID } from "./contract.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import {
  type InitialRetentionRepository,
  initialRetentionRequest,
  parseInitialRetentionReceipt,
} from "./initialEvidenceRetention.ts";

/** Service-only adapter for the existing ordinary ingestion owner. Authentication
 * and exact-byte readback belong to the handler; this adapter grants neither.
 */
export function initialEvidenceRepository(
  client: SupabaseClient,
  onResultBindingDispatch?: () => void,
): InitialRetentionRepository & {
  bindResult(
    owner: string,
    request: unknown,
    result: unknown,
    species: string | null,
    signal: AbortSignal,
  ): Promise<string>;
} {
  async function call(
    routine: string,
    owner: string,
    candidate: unknown,
    caller: AbortSignal,
    object?: string,
  ) {
    const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
    signal.throwIfAborted();
    const ownerID = historyUUID(owner);
    const request = await initialRetentionRequest(candidate);
    let onAbort = () => {};
    try {
      signal.throwIfAborted();
      const response = client.rpc(routine, {
        p_owner: ownerID,
        p_request: request,
        ...(object === undefined ? {} : { p_object: historyUUID(object) }),
      }).abortSignal(signal);
      const aborted = new Promise<never>((_, reject) => {
        onAbort = () =>
          reject(new HistoryError("analysis_history_unavailable"));
        signal.addEventListener("abort", onAbort, { once: true });
        if (signal.aborted) onAbort();
      });
      const result = await Promise.race([
        Promise.resolve(response).then(({ data, error }) => {
          if (error) {
            throw new HistoryError(
              error.message === "analysis_history_operation_conflict"
                ? "analysis_history_operation_conflict"
                : "analysis_history_unavailable",
            );
          }
          signal.throwIfAborted();
          return parseInitialRetentionReceipt(data, ownerID, request);
        }),
        aborted,
      ]);
      signal.throwIfAborted();
      return { schema_version: 1, ...result };
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
    async bindResult(owner, candidate, originalResult, species, caller) {
      const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
      signal.throwIfAborted();
      const ownerID = historyUUID(owner);
      // Own the result before suspension. Validate, but never replace it with
      // the parser's normalized projection: the original wire bytes are evidence.
      const result = structuredClone(originalResult);
      const validated = parseIdentifySuccessEnvelope({
        success: true,
        data: result,
      });
      const speciesID = species === null ? null : historyUUID(species);
      const request = await initialRetentionRequest(candidate);
      if (validated.data.scan_id !== request.scan_id) {
        throw new HistoryError("analysis_history_operation_conflict");
      }
      signal.throwIfAborted();
      let onAbort = () => {};
      try {
        // Mark uncertainty only at the RPC boundary, after local validation and
        // cancellation checks. A pre-dispatch failure has no accepted result.
        onResultBindingDispatch?.();
        const response = client.rpc("bind_owned_initial_result", {
          p_owner: ownerID,
          p_request: request,
          p_result: result,
          p_species: speciesID,
        }).abortSignal(signal);
        const aborted = new Promise<never>((_, reject) => {
          onAbort = () =>
            reject(new HistoryError("analysis_history_unavailable"));
          signal.addEventListener("abort", onAbort, { once: true });
          if (signal.aborted) onAbort();
        });
        const { data, error } = await Promise.race([
          Promise.resolve(response),
          aborted,
        ]);
        signal.throwIfAborted();
        if (error || typeof data !== "string" || !/^[0-9a-f]{64}$/.test(data)) {
          throw new HistoryError(
            error?.message === "analysis_history_operation_conflict"
              ? "analysis_history_operation_conflict"
              : "analysis_history_unavailable",
          );
        }
        return data;
      } catch (error) {
        if (
          error instanceof HistoryError &&
          error.code === "analysis_history_operation_conflict"
        ) throw error;
        throw new HistoryError("analysis_history_unavailable");
      } finally {
        signal.removeEventListener("abort", onAbort);
      }
    },
    reserve: (owner, request, signal) =>
      call("reserve_owned_initial_evidence", owner, request, signal),
    complete: (owner, request, object, signal) =>
      call("complete_owned_initial_evidence", owner, request, signal, object),
  };
}

/** Construction does no I/O; response and transport budgets are mandatory. */
export function createInitialEvidenceRepository() {
  return initialEvidenceRepository(
    createServiceRoleClientFromEnvironmentWithOptions({
      requestTimeoutMs: 5_000,
      maximumResponseBytes: 32_768,
    }),
  );
}
