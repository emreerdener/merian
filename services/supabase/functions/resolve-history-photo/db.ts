import type { SupabaseClient } from "@supabase/supabase-js";
import type { EvidenceIdentity } from "../_shared/analysisHistory/evidence.ts";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";

export async function resolvePhotoReceipt(
  client: SupabaseClient,
  identity: EvidenceIdentity,
) {
  const { data, error } = await client.rpc("resolve_owned_observation_photo", {
    p_owner: identity.owner_id,
    p_observation: identity.observation_id,
    p_analysis: identity.analysis_id,
    p_media: identity.media_id,
    p_reader: 8,
  });
  if (error) {
    // Never propagate database diagnostics or object identities into logging.
    if (error.message === "analysis_history_not_found") {
      throw new HistoryError("analysis_history_not_found");
    }
    throw new HistoryError("analysis_history_unavailable");
  }
  return data;
}
