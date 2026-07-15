import { createClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError, runBackground } from "../_shared/edgeHandler.ts";
import {
  fetchSpeciesObservationStats,
  parseSpeciesObservationStatsQuery,
  parseSpeciesObservationStatsRequest,
  SPECIES_OBSERVATION_STATS_SCHEMA_VERSION,
} from "./db.ts";

const freshStatsCacheHeaders = {
  "Cache-Control":
    "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800",
  "Vary": "Accept-Encoding",
};

const refreshingStatsCacheHeaders = {
  "Cache-Control":
    "public, max-age=30, s-maxage=60, stale-while-revalidate=300",
  "Vary": "Accept-Encoding",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const parsedRequestOrResponse = req.method === "GET"
      ? parseSpeciesObservationStatsQuery(new URL(req.url))
      : await parsePostRequest(req);
    if (parsedRequestOrResponse instanceof Response) {
      return parsedRequestOrResponse;
    }
    const parsedRequest = parsedRequestOrResponse;
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
      {
        runBackground,
        onBackgroundRefreshError: (error, context) => {
          logStructuredError("species_observation_stats_refresh_failed", {
            species_id: context.speciesId,
            scientific_name: context.scientificName,
            error: error instanceof Error ? error.message : String(error),
          });
        },
      },
    );

    return jsonResponse(
      {
        schema_version: SPECIES_OBSERVATION_STATS_SCHEMA_VERSION,
        data,
      },
      200,
      cacheHeadersForStatus(data.status),
    );
  } catch (error) {
    logStructuredError("species_observation_stats_fetch_failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});

async function parsePostRequest(req: Request) {
  const parsedBody = await parseJsonBody(req);
  if (parsedBody instanceof Response) {
    return parsedBody;
  }
  return parseSpeciesObservationStatsRequest(parsedBody);
}

function cacheHeadersForStatus(status: string): Record<string, string> {
  return status === "fresh" || status === "no_data"
    ? freshStatsCacheHeaders
    : refreshingStatsCacheHeaders;
}
