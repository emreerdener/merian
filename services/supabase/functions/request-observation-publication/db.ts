import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import type { PublicationOperationRequest } from "../_shared/analysisHistory/publicationOperation.ts";

export function publicationOperationRepository(client: SupabaseClient) {
  return {
    admit: async (
      owner: string,
      request: PublicationOperationRequest,
      ipHash: string,
    ): Promise<unknown> => {
      const { data, error } = await client.rpc(
        "admit_owned_observation_publication",
        {
          p_owner: owner,
          p_request: request,
          p_ip_hash: ipHash,
        },
      ).abortSignal(AbortSignal.timeout(12_000));
      if (error) {
        switch (error.message) {
          case "invalid_analysis_history":
          case "analysis_history_not_found":
          case "analysis_history_operation_conflict":
          case "analysis_history_revision_conflict":
          case "analysis_history_deleted":
            throw new HistoryError(error.message);
          default:
            throw new HistoryError("analysis_history_unavailable");
        }
      }
      return data;
    },
  };
}
