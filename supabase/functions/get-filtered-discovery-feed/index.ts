import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.31.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { userId, limit = 20 } = await req.json();

    if (!userId) {
      throw new Error("Invalid payload: Missing userId inside request.");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // Utilize Service Role Key to securely access shadowbanned users + global feeds via edge
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

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
    const blockedIds = blocksData.map((b: any) => b.blocked_id);
    const isolatedExclusions = [userId, ...blockedIds];

    // We format the array down securely to a nested TS query syntax string `(id1, id2)`
    const isolatedExclusionsString = `(${isolatedExclusions.join(",")})`;

    // 3. Query Scans matching Open bounds & Excluding Isolated Actors
    const { data: feedData, error: feedError } = await supabase
      .from("scans")
      .select(
        `
        *,
        species_dictionary (*)
      `,
      )
      .eq("geoprivacy", "open")
      .eq("is_live_capture", true)
      .not("user_id", "in", isolatedExclusionsString)
      .order("timestamp", { ascending: false })
      .limit(limit);

    if (feedError) {
      throw new Error(`Failed to map global feeds: ${feedError.message}`);
    }

    // Return the successful ordered feed block
    return new Response(JSON.stringify({ data: feedData }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
