import type { SupabaseClient } from "@supabase/supabase-js";
import type { EvidenceIdentity } from "../_shared/analysisHistory/evidence.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";

export async function resolveCompletedMediaReceipt(
  client: SupabaseClient,
  identity: EvidenceIdentity,
  protocol: 1 | 2 | 3,
) {
  const { data, error } = await client.rpc("resolve_owned_observation_media", {
    p_owner: identity.owner_id,
    p_observation: identity.observation_id,
    p_analysis: identity.analysis_id,
    p_media: identity.media_id,
    p_protocol: protocol === 3 ? 4 : protocol === 2 ? 3 : 2,
  });
  if (error) {
    throw new HistoryError(
      error.message === "analysis_history_not_found"
        ? "analysis_history_not_found"
        : "analysis_history_unavailable",
    );
  }
  return data;
}
