import type { SupabaseClient } from "@supabase/supabase-js";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import { createServiceRoleClientFromEnvironmentWithOptions } from "../serviceRoleClient.ts";
import { exactObject, HistoryError, historyUUID } from "./contract.ts";
import {
  type InitialRetentionRequest,
  initialRetentionRequest,
} from "./initialEvidenceRetention.ts";

/** An accepted provider result is a recovery input, not a completion proof.
 * Preserve its original fields for finalization; never infer them from a scan.
 */
export function parseAcceptedInitialResult(
  value: unknown,
  owner: string,
  request: InitialRetentionRequest,
) {
  historyUUID(owner);
  if (value === null) return null;
  const row = exactObject(structuredClone(value), [
    "schema_version",
    "owner_id",
    "scan_id",
    "generation",
    "evidence_digest",
    "result",
    "species_id",
    "result_digest",
  ]);
  const result = parseIdentifySuccessEnvelope({
    success: true,
    data: row.result,
  });
  if (
    row.schema_version !== 1 || row.owner_id !== owner ||
    row.scan_id !== request.scan_id || row.generation !== request.generation ||
    row.evidence_digest !== request.evidence_digest ||
    result.data.scan_id !== request.scan_id ||
    typeof row.result_digest !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.result_digest)
  ) throw new HistoryError("analysis_history_operation_conflict");
  const species = row.species_id === null ? null : historyUUID(row.species_id);
  return Object.freeze({
    result: row.result as Record<string, unknown>,
    speciesID: species,
    resultDigest: row.result_digest,
  });
}

/** Call only after exact-byte retention. Null means no bound provider result;
 * every transport, identity, retirement or readiness failure stays closed.
 */
export async function recoverAcceptedInitialResult(
  client: SupabaseClient,
  owner: string,
  candidate: unknown,
  caller: AbortSignal,
) {
  const signal = AbortSignal.any([caller, AbortSignal.timeout(5_000)]);
  signal.throwIfAborted();
  const ownerID = historyUUID(owner);
  const request = await initialRetentionRequest(candidate);
  signal.throwIfAborted();
  let onAbort = () => {};
  try {
    const response = client.rpc("recover_owned_initial_result", {
      p_owner: ownerID,
      p_request: request,
    }).abortSignal(signal);
    const aborted = new Promise<never>((_, reject) => {
      onAbort = () => reject(new HistoryError("analysis_history_unavailable"));
      signal.addEventListener("abort", onAbort, { once: true });
      if (signal.aborted) onAbort();
    });
    const { data, error } = await Promise.race([
      Promise.resolve(response),
      aborted,
    ]);
    signal.throwIfAborted();
    if (error) {
      throw new HistoryError(
        error.message === "analysis_history_operation_conflict"
          ? "analysis_history_operation_conflict"
          : "analysis_history_unavailable",
      );
    }
    return parseAcceptedInitialResult(data, ownerID, request);
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

/** The accepted result can approach the Identify envelope limit. Do not reuse
 * the small reservation-receipt response budget for this read. */
export function createInitialEvidenceRecovery() {
  const client = createServiceRoleClientFromEnvironmentWithOptions({
    requestTimeoutMs: 5_000,
    maximumResponseBytes: 1_048_576,
  });
  return (owner: string, request: unknown, signal: AbortSignal) =>
    recoverAcceptedInitialResult(client, owner, request, signal);
}
