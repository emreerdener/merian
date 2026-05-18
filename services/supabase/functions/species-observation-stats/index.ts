// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import {
  fetchSpeciesObservationStats,
  parseSpeciesObservationStatsRequest,
  SPECIES_OBSERVATION_STATS_SCHEMA_VERSION,
} from "./db.ts";

const publicStatsCacheHeaders = {
  "Cache-Control":
    "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800",
  "Vary": "Accept-Encoding",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;

    const parsedRequest = parseSpeciesObservationStatsRequest(parsedBody);
    if (!parsedRequest.scientificName) {
      return jsonResponse(
        { error: parsedRequest.error },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const data = await fetchSpeciesObservationStats(
      {
        speciesId: parsedRequest.speciesId,
        scientificName: parsedRequest.scientificName,
      },
      supabaseAdmin,
    );

    return jsonResponse(
      {
        schema_version: SPECIES_OBSERVATION_STATS_SCHEMA_VERSION,
        data,
      },
      200,
      publicStatsCacheHeaders,
    );
  } catch (error) {
    logStructuredError("species_observation_stats_fetch_failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
