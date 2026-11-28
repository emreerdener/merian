import type { PrivateErasureTarget } from "./handler.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import {
  type IdentitySafeErrorDetails,
  logIdentitySafeError,
} from "../_shared/edgeHandler.ts";

type Stage =
  | "retire_history"
  | "retire_video"
  | "retire_composition"
  | "claim"
  | "finish";

function databaseFailure(code: string): string {
  switch (code) {
    case "57014":
      return "database_query_cancelled";
    case "55P03":
      return "database_lock_unavailable";
    case "42501":
      return "database_permission_denied";
    case "42883":
      return "database_routine_missing";
    default:
      return "database_error";
  }
}

export function evidenceErasureRepository(
  client: SupabaseClient,
  dispatch: string,
  report: (event: string, details: IdentitySafeErrorDetails) => void =
    logIdentitySafeError,
) {
  function reportFailure(stage: Stage, code: string): void {
    try {
      // Only fixed stage/category tokens enter logs. Never pass the error,
      // dispatch, RPC arguments, response data, or object/claim identities.
      report("private_evidence_rpc_failed", { stage, code });
    } catch { /* Logging cannot change cleanup or settlement behavior. */ }
  }
  async function rpc(
    stage: Stage,
    name: string,
    args: Record<string, unknown>,
    parent: AbortSignal,
  ): Promise<unknown> {
    const signal = AbortSignal.any([parent, AbortSignal.timeout(12_000)]);
    let category = "rpc_transport_or_runtime";
    try {
      const { data, error } = await publicationAbortable(
        signal,
        () => client.rpc(name, args).abortSignal(signal),
      );
      signal.throwIfAborted();
      if (error) {
        category = databaseFailure(error.code);
        throw new Error("private_evidence_erasure_unavailable");
      }
      return data;
    } catch (error) {
      reportFailure(
        stage,
        parent.aborted
          ? "parent_cancelled"
          : signal.aborted
          ? "rpc_deadline"
          : category,
      );
      throw error;
    }
  }
  return {
    retire: (signal: AbortSignal) =>
      rpc(
        "retire_history",
        "retire_expired_observation_evidence_for_dispatch",
        {
          p_dispatch_id: dispatch,
        },
        signal,
      ),
    retireVideo: (signal: AbortSignal) =>
      rpc(
        "retire_video",
        "retire_expired_observation_video_evidence_for_dispatch",
        {
          p_dispatch_id: dispatch,
        },
        signal,
      ),
    retireComposition: (signal: AbortSignal) =>
      rpc(
        "retire_composition",
        "retire_expired_observation_composition_evidence_for_dispatch",
        {
          p_dispatch_id: dispatch,
        },
        signal,
      ),
    claim: (signal: AbortSignal) =>
      rpc("claim", "claim_private_evidence_erasure_v4_for_dispatch", {
        p_dispatch_id: dispatch,
      }, signal),
    finish: async (
      object: string,
      token: string,
      success: boolean,
      signal: AbortSignal,
      target: PrivateErasureTarget,
    ): Promise<boolean> => {
      const value = await rpc("finish", "finish_private_evidence_erasure_v4", {
        p_namespace: target.namespace,
        p_backend: target.backend_sha256,
        p_object: object,
        p_claim: token,
        p_success: success,
      }, signal);
      if (typeof value !== "boolean") {
        reportFailure("finish", "rpc_invalid_response");
        throw new Error("private_evidence_erasure_unavailable");
      }
      return value;
    },
  };
}
