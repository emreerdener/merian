import { serve } from "@std/http/server.ts";
import { createClient } from "@supabase/supabase-js";
import { requireAuth } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
// Utilize Service Role Key to securely access shadowbanned users + global feeds via edge
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { limit = 20 } = await req.json();

    const { user, response } = await requireAuth(req, supabase);
    if (response) return response;

    const userId = user!.id;

    // 1. Isolation Filter Hook - Query blocked_ids mapping the blocker explicitly
    const { data: blocksData, error: blocksError } = await supabase
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
    const { data: feedData, error: feedError } = await supabase
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

    // 4. Secure the Payload Coordinates Against Endangered Species Poaching Data Leaks
    // deno-lint-ignore no-explicit-any
    const sanitizedFeedData = feedData.map((scan: any) => {
      const species = scan.species_dictionary || {};
      const isProtected = 
        species.iucn_red_list_status === "vulnerable" || 
        species.iucn_red_list_status === "endangered" || 
        species.iucn_red_list_status === "critically_endangered" || 
        species.iucn_red_list_status === "near_threatened";

      if (isProtected) {
        // Obliterate exact pinpoint coordinates natively resolving anti-poaching security constraints natively
        delete scan.gps_lat_exact;
        delete scan.gps_long_exact;
        // Obscure public boundaries roughly to approx 11km blocks natively
        if (scan.gps_lat_public != null) scan.gps_lat_public = Math.round(scan.gps_lat_public * 10) / 10;
        if (scan.gps_long_public != null) scan.gps_long_public = Math.round(scan.gps_long_public * 10) / 10;
      }
      return scan;
    });

    // Return the successful ordered feed block
    return new Response(JSON.stringify({ data: sanitizedFeedData }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
