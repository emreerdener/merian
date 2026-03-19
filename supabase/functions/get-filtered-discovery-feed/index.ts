import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { limit = 20 } = await req.json();

    const userId = user.id;

    // 1. Isolation Filter Hook - Query blocked_ids mapping the blocker explicitly
    const { data: blocksData, error: blocksError } = await supabaseAdmin
      .from("user_blocks")
      .select("blocked_id")
      .eq("blocker_id", userId);

    if (blocksError) {
      throw new Error(
        `Failed to resolve Social Guard blocks map: ${blocksError.message}`,
      );
    }

    // 2. Build the Isolation Array
    const blockedIds = blocksData.map(
      (b: { blocked_id: string }) => b.blocked_id,
    );
    const isolatedExclusions = [userId, ...blockedIds];

    // The raw isolation array passed safely down into the PostgreSQL `in` bounds without string casting

    // 3. Query Scans matching Open bounds & Excluding Isolated Actors
    const { data: feedData, error: feedError } = await supabaseAdmin
      .from("scans")
      .select(
        `
        *,
        species_dictionary (*),
        users!inner(is_shadowbanned)
      `,
      )
      .eq("geoprivacy", "open")
      .eq("is_live_capture", true)
      .eq("users.is_shadowbanned", false)
      .not("user_id", "in", isolatedExclusions)
      .not("image_storage_urls", "eq", "{}")
      .order("timestamp", { ascending: false })
      .limit(limit);

    if (feedError) {
      throw new Error(`Failed to map global feeds: ${feedError.message}`);
    }

    // 4. Secure the Payload Coordinates Against Geoprivacy Vulnerabilities natively
    // deno-lint-ignore no-explicit-any
    const sanitizedFeedData = feedData.map((scan: any) => {
      // CRITICAL SEC FIX: Unconditionally delete exact pinpoint coordinates natively globally protecting User Geoprivacy
      delete scan.gps_lat_exact;
      delete scan.gps_long_exact;

      const species = scan.species_dictionary || {};
      const isProtected =
        species.iucn_red_list_status === "vulnerable" ||
        species.iucn_red_list_status === "endangered" ||
        species.iucn_red_list_status === "critically_endangered" ||
        species.iucn_red_list_status === "near_threatened";

      if (isProtected) {
        // Obscure public boundaries roughly to approx 11km blocks natively exclusively for protected targets
        if (scan.gps_lat_public != null)
          scan.gps_lat_public = Math.round(scan.gps_lat_public * 10) / 10;
        if (scan.gps_long_public != null)
          scan.gps_long_public = Math.round(scan.gps_long_public * 10) / 10;
      }
      return scan;
    });

    // Return the successful ordered feed block
    return new Response(JSON.stringify({ data: sanitizedFeedData }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
}));
