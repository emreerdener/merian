import { SupabaseClient } from "@supabase/supabase-js";

export interface ExploreMediaIncidentRow {
  post_id: string;
  scan_id: string;
  species_common_name: string;
  media_health_status: "degraded" | "quarantined";
  missing_media_count: number;
  total_media_count: number;
  media_quarantined_at: string | null;
  media_health_updated_at: string;
  missing_media_urls: string[];
}

export async function fetchOwnedExploreMediaIncidents(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreMediaIncidentRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_owned_explore_media_incidents",
    { self_id: userId },
  );
  if (error) {
    throw new Error(`fetchOwnedExploreMediaIncidents: ${error.message}`);
  }
  return (data ?? []) as ExploreMediaIncidentRow[];
}
