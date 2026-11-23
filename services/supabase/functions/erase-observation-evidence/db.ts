import type { PrivateErasureTarget } from "./handler.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";

export function evidenceErasureRepository(
  client: SupabaseClient,
  dispatch: string,
) {
  async function rpc(
    name: string,
    args: Record<string, unknown>,
    parent: AbortSignal,
  ): Promise<unknown> {
    const signal = AbortSignal.any([parent, AbortSignal.timeout(12_000)]);
    const { data, error } = await publicationAbortable(
      signal,
      () => client.rpc(name, args).abortSignal(signal),
    );
    signal.throwIfAborted();
    if (error) throw new Error("private_evidence_erasure_unavailable");
    return data;
  }
  return {
    retire: (signal: AbortSignal) =>
      rpc("retire_expired_observation_evidence_for_dispatch", {
        p_dispatch_id: dispatch,
      }, signal),
    retireVideo: (signal: AbortSignal) =>
      rpc("retire_expired_observation_video_evidence_for_dispatch", {
        p_dispatch_id: dispatch,
      }, signal),
    retireComposition: (signal: AbortSignal) =>
      rpc("retire_expired_observation_composition_evidence_for_dispatch", {
        p_dispatch_id: dispatch,
      }, signal),
    claim: (signal: AbortSignal) =>
      rpc("claim_private_evidence_erasure_v4_for_dispatch", {
        p_dispatch_id: dispatch,
      }, signal),
    finish: async (
      object: string,
      token: string,
      success: boolean,
      signal: AbortSignal,
      target: PrivateErasureTarget,
    ): Promise<boolean> => {
      const value = await rpc("finish_private_evidence_erasure_v4", {
        p_namespace: target.namespace,
        p_backend: target.backend_sha256,
        p_object: object,
        p_claim: token,
        p_success: success,
      }, signal);
      if (typeof value !== "boolean") {
        throw new Error("private_evidence_erasure_unavailable");
      }
      return value;
    },
  };
}
