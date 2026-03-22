import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { limit = 20 } = await req.json();

    // 1. Isolation Filter Hook - Query blocked_ids mapping the blocker explicitly
    const { data: blocksData, error: blocksError } = await supabaseAdmin
      .from("user_blocks")
      .select("blocked_id")
      .eq("blocker_id", user.id);

    if (blocksError) {
      throw new Error(`Failed to resolve Social Guard blocks map: ${blocksError.message}`);
    }

    // 2. Build the Isolation Array
    const blockedIds = blocksData.map((b: { blocked_id: string }) => b.blocked_id);
    const isolatedExclusions = [user.id, ...blockedIds];

    // The raw isolation array passed safely down into the PostgreSQL `in` bounds without string casting
    // 3. Query Scans matching Open bounds & Excluding Isolated Actors
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
      .not("user_id", "in", `(${isolatedExclusions.join(",")})`)
      .not("image_storage_urls", "eq", "{}")
      .order("timestamp", { ascending: false })
      .limit(limit);

    if (feedError) {
      throw new Error(`Failed to map global feeds: ${feedError.message}`);
    }

    // 4. Secure the Payload Coordinates Against Geoprivacy Vulnerabilities natively
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

      // CRITICAL SEC FIX: Unconditionally delete exact pinpoint coordinates natively globally protecting User Geoprivacy
      delete scan.gps_lat_exact;
      delete scan.gps_long_exact;

      const species = scan.species_dictionary || {};
      const isProtected = ["vulnerable", "endangered", "critically_endangered", "near_threatened"]
        .includes(species.iucn_red_list_status || "");

      if (isProtected) {
        // Obscure public boundaries roughly to approx 11km blocks natively exclusively for protected targets
        if (typeof scan.gps_lat_public === "number") {
          scan.gps_lat_public = Math.round(scan.gps_lat_public * 10) / 10;
        }
        if (typeof scan.gps_long_public === "number") {
          scan.gps_long_public = Math.round(scan.gps_long_public * 10) / 10;
        }
      }
      
      return scan;
    });

    // Return the successful ordered feed block
    return jsonResponse({ data: sanitizedFeedData }, 200);
  })
);
