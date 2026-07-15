import { SupabaseClient } from "@supabase/supabase-js";
import { ExploreFeedFilter, type ExplorePostMediaItem } from "../_shared/explore.ts";
import type { PetIdentification } from "../_shared/identify/types.ts";

export interface ExploreFeedRow {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean;
  hashtags?: string[];
  species_common_name: string;
  species_scientific_name: string;
  pet_identification?: PetIdentification | null;
  public_location_label?: string | null;
  location_sharing: "open" | "obscured" | "private";
  time_of_day?: string | null;
  current_month?: number | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  like_count: number;
  comment_count: number;
  viewer_has_liked: boolean;
  is_owned_by_viewer: boolean;
  ranking_value?: number | null;
  media_items?: ExplorePostMediaItem[];
}

interface ExploreFeedCursor {
  beforeSharedAt: string | null;
  beforePostId: string | null;
  beforeRankingValue: number | null;
}

interface ExploreFeedLocation {
  latitude: number | null;
  longitude: number | null;
}

export async function fetchExploreFeed(
  userId: string,
  limit: number,
  filter: ExploreFeedFilter,
  cursor: ExploreFeedCursor,
  location: ExploreFeedLocation,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreFeedRow[]> {
  let rpcName = "get_explore_feed";
  const rpcArgs: Record<string, unknown> = {
    self_id: userId,
    max_limit: limit,
  };

  switch (filter) {
    case "recent":
      rpcArgs.before_shared_at = cursor.beforeSharedAt;
      rpcArgs.before_post_id = cursor.beforePostId;
      break;
    case "following":
      rpcName = "get_explore_feed_following";
      rpcArgs.before_shared_at = cursor.beforeSharedAt;
      rpcArgs.before_post_id = cursor.beforePostId;
      break;
    case "trending":
      rpcName = "get_explore_feed_trending";
      rpcArgs.before_ranking_value = cursor.beforeRankingValue;
      rpcArgs.before_shared_at = cursor.beforeSharedAt;
      rpcArgs.before_post_id = cursor.beforePostId;
      break;
    case "nearby":
      rpcName = "get_explore_feed_nearby";
      rpcArgs.viewer_latitude = location.latitude;
      rpcArgs.viewer_longitude = location.longitude;
      rpcArgs.before_shared_at = cursor.beforeSharedAt;
      rpcArgs.before_post_id = cursor.beforePostId;
      break;
  }

  const { data, error } = await supabaseAdmin.rpc(rpcName, rpcArgs);

  if (error) {
    throw new Error(`Failed to fetch Explore feed: ${error.message}`);
  }

  return (data ?? []) as ExploreFeedRow[];
}
