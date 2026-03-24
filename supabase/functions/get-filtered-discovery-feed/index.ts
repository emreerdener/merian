import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { limit = 20 } = await req.json();

    // 1. Fetch block list for the requesting user
    const { data: blocksData, error: blocksError } = await supabaseAdmin
      .from("user_blocks")
      .select("blocked_id")
      .eq("blocker_id", user.id);

    if (blocksError) {
      throw new Error(`Failed to fetch block list: ${blocksError.message}`);
    }

    // 2. Build exclusion list: self + blocked users
    const blockedIds = blocksData.map((b: { blocked_id: string }) => b.blocked_id);
    const excludedIds = [user.id, ...blockedIds];

    // 3. Query public scans, excluding self and blocked users
    const { data: feedData, error: feedError } = await supabaseAdmin
      .from("scans")
      .select(`
        *,
        species_dictionary (*),
        users!inner(is_shadowbanned)
      `)
      .eq("geoprivacy", "open")
      .eq("is_live_capture", true)
      .eq("users.is_shadowbanned", false)
      .not("user_id", "in", `(${excludedIds.map(id => `"${id}"`).join(",")})`)
      .not("image_storage_urls", "eq", "{}")
      .order("timestamp", { ascending: false })
      .limit(limit);

    if (feedError) {
      throw new Error(`Failed to fetch discovery feed: ${feedError.message}`);
    }

    // 4. Sanitize coordinates for geoprivacy
    interface SpeciesDictionary {
      iucn_red_list_status?: string;
    }

    interface FeedScan {
      gps_lat_exact?: number;
      gps_long_exact?: number;
      gps_lat_public?: number;
      gps_long_public?: number;
      species_dictionary?: SpeciesDictionary;
      [key: string]: unknown;
    }

    const sanitizedFeedData = feedData.map((row) => {
      const scan = row as FeedScan;

      // Always strip exact coordinates
      delete scan.gps_lat_exact;
      delete scan.gps_long_exact;

      const species = scan.species_dictionary || {};
      const isProtected = ["vulnerable", "endangered", "critically_endangered", "near_threatened"]
        .includes(species.iucn_red_list_status || "");

      if (isProtected) {
        // Round to ~11km resolution for protected species
        if (typeof scan.gps_lat_public === "number") {
          scan.gps_lat_public = Math.round(scan.gps_lat_public * 10) / 10;
        }
        if (typeof scan.gps_long_public === "number") {
          scan.gps_long_public = Math.round(scan.gps_long_public * 10) / 10;
        }
      }

      return scan;
    });

    return jsonResponse({ data: sanitizedFeedData }, 200);
  })
);
