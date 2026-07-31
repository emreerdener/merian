import { SupabaseClient } from "@supabase/supabase-js";
import type { ExplorePostMediaItem } from "../_shared/explore.ts";

export type CommunityIdentificationActivityType =
  | "suggestion_burst"
  | "consensus_changed"
  | "resolved";

export type CommunityIdentificationActivityScope = "all" | "mine";

export type CommunityIdentificationActivityGroup =
  | "all"
  | "plants"
  | "birds"
  | "insects"
  | "fungi"
  | "mammals"
  | "reptiles_amphibians";

export interface CommunityIdentificationActivityRow {
  activity_id: string;
  activity_type: CommunityIdentificationActivityType;
  request_id: string;
  post_id: string;
  scan_id: string;
  hero_image_url?: string | null;
  activity_at: string;
  suggestion_count: number;
  recent_actor_names: string[];
  taxon_id?: string | null;
  taxon_common_name?: string | null;
  taxon_scientific_name?: string | null;
  taxon_rank?: string | null;
  consensus_score?: number | null;
  request_group: CommunityIdentificationActivityGroup;
  media_items?: ExplorePostMediaItem[];
}

export interface CommunityIdentificationActivityCursor {
  beforeActivityAt: string | null;
  beforeActivityId: string | null;
}

export async function fetchCommunityIdentificationActivity(
  userId: string,
  scope: CommunityIdentificationActivityScope,
  group: CommunityIdentificationActivityGroup,
  limit: number,
  cursor: CommunityIdentificationActivityCursor,
  supabaseAdmin: SupabaseClient,
): Promise<CommunityIdentificationActivityRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_community_identification_activity",
    {
      self_id: userId,
      max_limit: limit,
      before_activity_at: cursor.beforeActivityAt,
      before_activity_id: cursor.beforeActivityId,
      request_scope: scope,
      request_group_filter: group,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch community identification activity: ${error.message}`,
    );
  }

  return (data ?? []) as CommunityIdentificationActivityRow[];
}
