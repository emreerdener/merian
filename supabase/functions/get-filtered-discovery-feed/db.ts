import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { FeedScan } from "./types.ts";

export async function fetchBlockedUserIds(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string[]> {
  const { data: blocksData, error: blocksError } = await supabaseAdmin
    .from("user_blocks")
    .select("blocked_id")
    .eq("blocker_id", userId);

  if (blocksError) {
    throw new Error(`Failed to fetch block list: ${blocksError.message}`);
  }

  return blocksData.map((b: { blocked_id: string }) => b.blocked_id);
}

export async function fetchDiscoveryFeed(
  excludedIds: string[],
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<FeedScan[]> {
  const { data: feedData, error: feedError } = await supabaseAdmin
    .from("scans")
    .select(`
        id,
        user_id,
        timestamp,
        image_storage_urls,
        gps_lat_public,
        gps_long_public,
        ecology_type,
        is_invasive,
        is_live_capture,
        colors,
        semantic_location,
        weather_condition,
        weather_temperature_f,
        ai_confidence_score,
        species_dictionary (
          id,
          scientific_name,
          common_names,
          wikipedia_url,
          reference_image_url,
          iucn_red_list_status,
          hazard_type,
          kingdom
        ),
        users!inner(is_shadowbanned)
      `)
    .eq("geoprivacy", "open")
    .eq("is_live_capture", true)
    .eq("users.is_shadowbanned", false)
    .not("user_id", "in", `(${excludedIds.map((id) => `"${id}"`).join(",")})`)
    .not("image_storage_urls", "eq", "{}")
    .order("timestamp", { ascending: false })
    .limit(limit);

  if (feedError) {
    throw new Error(`Failed to fetch discovery feed: ${feedError.message}`);
  }

  return feedData as FeedScan[];
}
