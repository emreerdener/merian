import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import type { EvidenceIdentity } from "../_shared/analysisHistory/evidence.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";
import type { UploadCohort } from "./handler.ts";
export function evidenceUploadRepository(client: SupabaseClient) {
  async function rpc(
    name: string,
    args: Record<string, unknown>,
    parent: AbortSignal,
  ) {
    const signal = AbortSignal.any([parent, AbortSignal.timeout(12_000)]);
    const { data, error } = await publicationAbortable(
      signal,
      () => client.rpc(name, args).abortSignal(signal),
    );
    if (error) {
      switch (error.message) {
        case "analysis_history_not_found":
        case "analysis_history_operation_conflict":
        case "analysis_history_evidence_unavailable":
          throw new HistoryError(error.message);
        default:
          throw new HistoryError("analysis_history_unavailable");
      }
    }
    return data;
  }
  return {
    reserve(input: UploadCohort, signal: AbortSignal) {
      return rpc("reserve_owned_observation_evidence_cohort", {
        p_owner: input.owner_id,
        p_observation: input.observation_id,
        p_analysis: input.analysis_id,
        p_items: input.items,
      }, signal);
    },
    complete(input: EvidenceIdentity, object: string, signal: AbortSignal) {
      return rpc("complete_owned_observation_evidence_upload", {
        p_owner: input.owner_id,
        p_observation: input.observation_id,
        p_analysis: input.analysis_id,
        p_media: input.media_id,
        p_object: object,
      }, signal);
    },
  };
}
