import { SupabaseClient } from "@supabase/supabase-js";
import { ExploreMapPostRow } from "./types.ts";

export async function fetchExploreMapPosts(
  userId: string,
  northLatitude: number,
  southLatitude: number,
  eastLongitude: number,
  westLongitude: number,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreMapPostRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_map_posts", {
    self_id: userId,
    north_latitude: northLatitude,
    south_latitude: southLatitude,
    east_longitude: eastLongitude,
    west_longitude: westLongitude,
    max_limit: limit,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore map posts: ${error.message}`);
  }

  return (data ?? []) as ExploreMapPostRow[];
}
