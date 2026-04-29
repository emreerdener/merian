import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreFeedRow {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_avatar_url?: string | null;
  species_common_name: string;
  species_scientific_name: string;
  public_location_label?: string | null;
  time_of_day?: string | null;
  current_month?: number | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  like_count: number;
  comment_count: number;
  viewer_has_liked: boolean;
  is_owned_by_viewer: boolean;
}

interface ExploreFeedCursor {
  beforeSharedAt: string | null;
  beforePostId: string | null;
}

export async function fetchExploreFeed(
  userId: string,
  limit: number,
  cursor: ExploreFeedCursor,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreFeedRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_feed", {
    self_id: userId,
    max_limit: limit,
    before_shared_at: cursor.beforeSharedAt,
    before_post_id: cursor.beforePostId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore feed: ${error.message}`);
  }

  return (data ?? []) as ExploreFeedRow[];
}
