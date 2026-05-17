// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

import { FeedScan } from "./types.ts";
import { fetchDiscoveryFeed } from "./db.ts";

function sanitizeFeedData(feedData: FeedScan[]): FeedScan[] {
  return feedData.map((scan) => {
    // Always strip exact coordinates before transmitting over HTTP
    delete scan.gps_lat_exact;
    delete scan.gps_long_exact;

    const species = scan.species_dictionary || {};
    const isProtected = [
      "vulnerable",
      "endangered",
      "critically_endangered",
      "near_threatened",
    ].includes(species.iucn_red_list_status || "");

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
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const MAX_FEED_LIMIT = 100;
    let limit = 20;
    try {
      const body = await req.json();
      if (body.limit && typeof body.limit === "number") {
        limit = Math.min(Math.floor(body.limit), MAX_FEED_LIMIT);
      }
    } catch {
      // Body is optional, defaults to 20
    }

    // Fetch the filtered feed directly via the RPC
    const feedData = await fetchDiscoveryFeed(user.id, limit, supabaseAdmin);

    // Sanitize coordinates for Geoprivacy compliance
    const sanitizedFeedData = sanitizeFeedData(feedData);

    return jsonResponse({ data: sanitizedFeedData }, 200);
  }),
);
