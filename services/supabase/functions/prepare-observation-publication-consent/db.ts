import type { SupabaseClient } from "@supabase/supabase-js";
import {
  HistoryError,
  historyUUID,
} from "../_shared/analysisHistory/contract.ts";
import {
  parsePublicationConsentRequest,
  type PublicationConsentRequest,
} from "../_shared/analysisHistory/publicationConsent.ts";
import { publicationAbortable } from "../_shared/analysisHistory/publicationDeadline.ts";

export function publicationConsentRepository(client: SupabaseClient) {
  return {
    async read(
      owner: string,
      input: PublicationConsentRequest,
    ): Promise<unknown> {
      const request = parsePublicationConsentRequest(input);
      const ownerID = historyUUID(owner);
      const signal = AbortSignal.timeout(12_000);
      try {
        const { data, error } = await publicationAbortable(
          signal,
          () =>
            client.rpc("prepare_owned_observation_publication_consent", {
              p_owner: ownerID,
              p_observation: request.observation_id,
              p_analysis: request.analysis_id,
            }).abortSignal(signal),
        );
        if (error) {
          switch (error.message) {
            case "invalid_identification_review":
              throw new HistoryError("analysis_history_operation_conflict");
            case "analysis_history_evidence_unavailable":
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
