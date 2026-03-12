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
    const { limit = 20 } = await req.json();

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // Utilize Service Role Key to securely access shadowbanned users + global feeds via edge
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization")?.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const userId = user.id;

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
        species_dictionary (*)
      `,
      )
      .eq("geoprivacy", "open")
      .eq("is_live_capture", true)
      .not("user_id", "in", isolatedExclusions)
      .not("image_storage_urls", "eq", "{}")
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
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: errorMessage }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
