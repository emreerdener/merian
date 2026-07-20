import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeLimit,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { fetchExploreMapPosts } from "./db.ts";
import { buildExploreMapPayload } from "./cluster.ts";
import { normalizeExploreMapRows } from "./contract.ts";
import { normalizeMediaTypes, normalizeSpeciesCategories } from "./input.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeCoordinate(
  value: unknown,
  label: string,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw makeHttpError(400, `${label} must be a valid number.`);
  }

  if (value < minimum || value > maximum) {
    throw makeHttpError(
      400,
      `${label} must be between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

function normalizeZoomLevel(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }

  return Math.max(0, Math.min(value, 20));
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const northLatitude = normalizeCoordinate(
      body.north_latitude,
      "north_latitude",
      -90,
      90,
    );
    const southLatitude = normalizeCoordinate(
      body.south_latitude,
      "south_latitude",
      -90,
      90,
    );
    const eastLongitude = normalizeCoordinate(
      body.east_longitude,
      "east_longitude",
      -180,
      180,
    );
    const westLongitude = normalizeCoordinate(
      body.west_longitude,
      "west_longitude",
      -180,
      180,
    );
    const zoomLevel = normalizeZoomLevel(body.zoom_level);
    const limit = normalizeLimit(body.limit, 500, 500);
    const speciesCategories = normalizeSpeciesCategories(
      body.species_categories,
    );
    const mediaTypes = normalizeMediaTypes(body.media_types);

    const rows = normalizeExploreMapRows(
      await withExplorePostMediaItems(
        await withExploreAuthorUsernames(
          await withExploreAuthorProBadges(
            await fetchExploreMapPosts(
              user.id,
              northLatitude,
              southLatitude,
              eastLongitude,
              westLongitude,
              limit,
              supabaseAdmin,
            ),
            supabaseAdmin,
          ),
          supabaseAdmin,
        ),
        supabaseAdmin,
      ),
    );

    return jsonResponse(
      buildExploreMapPayload(rows, zoomLevel, speciesCategories, mediaTypes),
      200,
    );
  })
);
