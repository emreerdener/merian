import type { SupabaseClient } from "@supabase/supabase-js";
import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  parsePublicationTargetRequest,
  type PublicationTargetRequest,
} from "../_shared/analysisHistory/publicationTarget.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";

export function publicationTargetRepository(client: SupabaseClient) {
  return {
    async read(
      owner: string,
      input: PublicationTargetRequest,
    ): Promise<unknown> {
      const request = parsePublicationTargetRequest(input);
      const ownerID = historyUUID(owner);
      const signal = AbortSignal.timeout(12_000);
      try {
        const { data, error } = await publicationAbortable(
          signal,
          () =>
            client.rpc("read_owned_observation_publication_target", {
              p_owner: ownerID,
              p_observation: request.observation_id,
            }).abortSignal(signal),
        );
        if (error) {
          switch (error.message) {
            case "analysis_history_not_found":
            case "analysis_history_deleted":
            case "analysis_history_revision_conflict":
            case "analysis_history_operation_conflict":
              throw new HistoryError(error.message);
            default:
              throw new HistoryError("analysis_history_unavailable");
          }
        }
        return data;
      } catch (error) {
        if (error instanceof HistoryError) throw error;
        throw new HistoryError("analysis_history_unavailable");
      }
    },
  };
}
