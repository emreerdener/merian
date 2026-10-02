import { SupabaseClient } from "@supabase/supabase-js";
import { FeedScan } from "./types.ts";
import { parseAIIdentificationReview } from "../_shared/identify/aiIdentificationReview.ts";

/** Legacy feed cannot display review authority; never leak raw owner history or old species. */
export function projectDiscoveryScan(scan: FeedScan): FeedScan {
  const { ai_identification_review, ...publicScan } = scan;
  if (ai_identification_review == null) return publicScan;
  const review = parseAIIdentificationReview(ai_identification_review);
  if (review.state !== "clear" || review.community !== null) {
    delete publicScan.species_dictionary;
    delete publicScan.ai_confidence_score;
    // Without a current species this legacy feed cannot apply its IUCN mask.
    delete publicScan.gps_lat_public;
    delete publicScan.gps_long_public;
    delete publicScan.gps_lat_exact;
    delete publicScan.gps_long_exact;
  }
  return publicScan;
}

async function fetchBlockedUserIds(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string[]> {
  const { data: blocksData, error: blocksError } = await supabaseAdmin
    .from("user_blocks")
    .select("blocked_id")
    .eq("blocker_id", userId)
    .limit(10000);

  if (blocksError) {
    throw new Error(`Failed to fetch block list: ${blocksError.message}`);
  }

  return blocksData.map((b: { blocked_id: string }) => b.blocked_id);
}

async function fetchDiscoveryFeedViaFallback(
  selfId: string,
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
        ai_identification_review,
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
    .neq("user_id", selfId)
    .not("image_storage_urls", "eq", "{}")
    .order("timestamp", { ascending: false })
    .limit(limit);

  if (feedError) {
    throw new Error(`Failed to fetch discovery feed: ${feedError.message}`);
  }

  return (feedData as FeedScan[]).map(projectDiscoveryScan);
}

function isMissingFilteredFeedRpc(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("get_filtered_discovery_feed") ||
    message.includes("PGRST202");
}

function fallbackFetchLimit(limit: number, blockedCount: number): number {
  if (blockedCount <= 0) return limit;
  const extraSlots = Math.min(
    limit,
    Math.max(Math.ceil(limit * 0.2), Math.min(blockedCount, 50)),
  );
  return limit + extraSlots;
}

export async function fetchDiscoveryFeed(
  selfId: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<FeedScan[]> {
  try {
    const { data: feedData, error: feedError } = await supabaseAdmin
      .rpc("get_filtered_discovery_feed", { self_id: selfId, max_limit: limit })
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
        ai_identification_review,
          species_dictionary (
            id,
            scientific_name,
            common_names,
            wikipedia_url,
            reference_image_url,
            iucn_red_list_status,
            hazard_type,
            kingdom
          )
        `);

    if (feedError) {
      throw new Error(`Failed to fetch discovery feed: ${feedError.message}`);
    }

    return (feedData as FeedScan[]).map(projectDiscoveryScan);
  } catch (error) {
    if (!isMissingFilteredFeedRpc(error)) {
      throw error;
    }

    console.warn(
      "[get-filtered-discovery-feed] RPC missing; falling back to JS block filtering.",
    );
    const blockedIds = await fetchBlockedUserIds(selfId, supabaseAdmin);
    const rawFeed = await fetchDiscoveryFeedViaFallback(
      selfId,
      fallbackFetchLimit(limit, blockedIds.length),
      supabaseAdmin,
    );
    const excludedSet = new Set(blockedIds);
    return rawFeed.filter((scan) =>
      scan.user_id != null && !excludedSet.has(scan.user_id)
    ).slice(0, limit);
  }
}
