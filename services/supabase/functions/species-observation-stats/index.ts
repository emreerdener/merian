import {
  corsHeaders,
  jsonResponse,
  publicErrorResponse,
} from "../_shared/http.ts";
import {
  logStructuredError,
  runBackground,
  serveEdge,
} from "../_shared/edgeHandler.ts";
import { readRequestJsonWithinBudget } from "../_shared/mediaBudgets.ts";
import { createServiceRoleClientFromEnvironment } from "../_shared/serviceRoleClient.ts";
import {
  fetchSpeciesObservationStats,
  parseSpeciesObservationStatsQuery,
  parseSpeciesObservationStatsRequest,
  SPECIES_OBSERVATION_STATS_SCHEMA_VERSION,
} from "./db.ts";
import {
  resolveSpeciesObservationStatsSecurityContext,
  SpeciesObservationStatsError,
} from "./security.ts";

const MAX_REQUEST_BODY_BYTES = 4 * 1024;

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

const privateErrorHeaders = {
  "Cache-Control": "private, no-store",
  "Vary": "Authorization, Accept-Encoding",
};

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return jsonResponse(
      { error: "Method not allowed" },
      405,
      privateErrorHeaders,
    );
  }

  try {
    const parsedRequestOrResponse = req.method === "GET"
      ? parseSpeciesObservationStatsQuery(new URL(req.url))
      : await parsePostRequest(req);
    if (parsedRequestOrResponse instanceof Response) {
      return privateNoStoreResponse(parsedRequestOrResponse);
    }
    const parsedRequest = parsedRequestOrResponse;
    if (!parsedRequest.speciesId || !parsedRequest.scientificName) {
      return jsonResponse(
        { error: parsedRequest.error },
        parsedRequest.status ?? 400,
        privateErrorHeaders,
      );
    }

    const supabaseAdmin = createServiceRoleClientFromEnvironment(
      Deno.env.get("SUPABASE_URL") ?? "",
    );
    const securityContext = await resolveSpeciesObservationStatsSecurityContext(
      req,
      supabaseAdmin,
    );

    const data = await fetchSpeciesObservationStats(
      {
        speciesId: parsedRequest.speciesId,
        scientificName: parsedRequest.scientificName,
      },
      supabaseAdmin,
      {
        securityContext,
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
      code: error instanceof SpeciesObservationStatsError
        ? error.code
        : "species_stats_unavailable",
      error: error instanceof Error ? error.message : String(error),
    });
    if (error instanceof SpeciesObservationStatsError) {
      return publicErrorResponse(
        req,
        error.status,
        error.code,
        error.message,
        {
          extraHeaders: privateErrorHeaders,
          retryAfterSeconds: error.retryAfterSeconds,
        },
      );
    }
    return publicErrorResponse(
      req,
      503,
      "species_stats_unavailable",
      "Species statistics are temporarily unavailable.",
      {
        extraHeaders: privateErrorHeaders,
        retryAfterSeconds: 30,
      },
    );
  }
});

async function parsePostRequest(req: Request) {
  const bodyResult = await readRequestJsonWithinBudget<unknown>(
    req,
    MAX_REQUEST_BODY_BYTES,
  );
  if (bodyResult.error || bodyResult.value === undefined) {
    return jsonResponse(
      { error: bodyResult.error?.message ?? "Invalid JSON body" },
      bodyResult.error?.status ?? 400,
    );
  }
  const parsedBody = bodyResult.value;
  if (
    !parsedBody ||
    typeof parsedBody !== "object" ||
    Array.isArray(parsedBody)
  ) {
    return jsonResponse({ error: "JSON body must be an object." }, 400);
  }
  return parseSpeciesObservationStatsRequest(
    parsedBody as Record<string, unknown>,
  );
}

function cacheHeadersForStatus(status: string): Record<string, string> {
  return status === "fresh" || status === "no_data"
    ? freshStatsCacheHeaders
    : refreshingStatsCacheHeaders;
}

function privateNoStoreResponse(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(privateErrorHeaders)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
