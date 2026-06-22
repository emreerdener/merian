import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeLimit,
  refreshExploreAuthorStateBestEffort,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";
import { fetchExploreMapPosts } from "./db.ts";
import { buildExploreMapPayload } from "./cluster.ts";
import { ExploreMapSpeciesCategory } from "./types.ts";

const ALLOWED_SPECIES_CATEGORIES = new Set<ExploreMapSpeciesCategory>([
  "plants",
  "fungi",
  "birds",
  "mammals",
  "reptiles",
  "amphibians",
  "fish",
  "insects",
  "arachnids",
  "other",
]);

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

function normalizeSpeciesCategories(
  value: unknown,
): ExploreMapSpeciesCategory[] {
  if (!Array.isArray(value)) return [];

  const categories: ExploreMapSpeciesCategory[] = [];
  for (const rawCategory of value) {
    if (typeof rawCategory !== "string") continue;
    const category = rawCategory.trim()
      .toLowerCase() as ExploreMapSpeciesCategory;
    if (
      ALLOWED_SPECIES_CATEGORIES.has(category) && !categories.includes(category)
    ) {
      categories.push(category);
    }
  }

  return categories;
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

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-map-points",
    );

    const rows = await withExploreAuthorUsernames(
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
    );

    return jsonResponse(
      buildExploreMapPayload(rows, zoomLevel, speciesCategories),
      200,
    );
  })
);
