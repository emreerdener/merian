import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";

export function evidenceErasureRepository(client: SupabaseClient) {
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
      rpc("retire_expired_observation_evidence", {}, signal),
    claim: (signal: AbortSignal) =>
      rpc("claim_observation_evidence_erasure", {}, signal),
    finish: async (
      object: string,
      token: string,
      success: boolean,
      signal: AbortSignal,
    ): Promise<boolean> => {
      const value = await rpc("finish_observation_evidence_erasure", {
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
