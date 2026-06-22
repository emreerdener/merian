import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface CommunityIdentificationFeedRow {
  request_id: string;
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  requested_at: string;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean;
  taxonomy_version_id?: string | null;
  projection_state?: string | null;
  consensus_processing_state?: string | null;
  current_taxon_id?: string | null;
  current_common_name?: string | null;
  current_scientific_name?: string | null;
  current_rank?: string | null;
  current_path?: string | null;
  initial_taxon_id?: string | null;
  initial_common_name?: string | null;
  initial_scientific_name?: string | null;
  initial_rank?: string | null;
  initial_path?: string | null;
  request_group?: CommunityIdentificationRequestGroup;
  consensus_score?: number | null;
  identification_count: number;
  viewer_has_identified: boolean;
  public_location_label?: string | null;
  location_sharing: "open" | "obscured" | "private";
}

export interface CommunityIdentificationCursor {
  beforeRequestedAt: string | null;
  beforeRequestId: string | null;
}

export interface CommunityIdentificationLocation {
  latitude: number | null;
  longitude: number | null;
}

export type CommunityIdentificationFeedScope = "all" | "mine";
export type CommunityIdentificationRequestGroup =
  | "all"
  | "plants"
  | "birds"
  | "insects"
  | "fungi"
  | "mammals"
  | "reptiles_amphibians";

export async function fetchCommunityIdentificationFeed(
  userId: string,
  scope: CommunityIdentificationFeedScope,
  group: CommunityIdentificationRequestGroup,
  limit: number,
  cursor: CommunityIdentificationCursor,
  location: CommunityIdentificationLocation,
  supabaseAdmin: SupabaseClient,
): Promise<CommunityIdentificationFeedRow[]> {
  const rpcArgs = {
    self_id: userId,
    max_limit: limit,
    before_requested_at: cursor.beforeRequestedAt,
    before_request_id: cursor.beforeRequestId,
    viewer_latitude: location.latitude,
    viewer_longitude: location.longitude,
    request_scope: scope,
    request_group_filter: group,
  };

  const { data, error } = await supabaseAdmin.rpc(
    "get_community_identification_feed",
    rpcArgs,
  );

  if (error) {
    throw new Error(
      `Failed to fetch community identification feed: ${error.message}`,
    );
  }

  return (data ?? []) as CommunityIdentificationFeedRow[];
}
