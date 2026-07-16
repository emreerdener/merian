export type ExploreMediaType = "image" | "video" | "audio";

export type ExploreSpeciesCategory =
  | "plants"
  | "fungi"
  | "birds"
  | "mammals"
  | "reptiles"
  | "amphibians"
  | "fish"
  | "insects"
  | "arachnids"
  | "other";

export const DEFAULT_EXPLORE_NEARBY_RADIUS_MILES = 50;
export const MIN_EXPLORE_NEARBY_RADIUS_MILES = 1;
export const MAX_EXPLORE_NEARBY_RADIUS_MILES = 100;

const ALLOWED_SPECIES_CATEGORIES = new Set<ExploreSpeciesCategory>([
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

const ALLOWED_MEDIA_TYPES = new Set<ExploreMediaType>([
  "image",
  "video",
  "audio",
]);

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeStringFilters<T extends string>(
  value: unknown,
  allowedValues: Set<T>,
): T[] {
  if (!Array.isArray(value)) return [];

  const normalized: T[] = [];
  for (const rawValue of value) {
    if (typeof rawValue !== "string") continue;
    const candidate = rawValue.trim().toLowerCase() as T;
    if (allowedValues.has(candidate) && !normalized.includes(candidate)) {
      normalized.push(candidate);
    }
  }

  return normalized;
}

export function normalizeExploreSpeciesCategories(
  value: unknown,
): ExploreSpeciesCategory[] {
  return normalizeStringFilters(value, ALLOWED_SPECIES_CATEGORIES);
}

export function normalizeExploreMediaTypes(
  value: unknown,
): ExploreMediaType[] {
  return normalizeStringFilters(value, ALLOWED_MEDIA_TYPES);
}

export function normalizeExploreNearbyRadiusMiles(value: unknown): number {
  if (value == null) return DEFAULT_EXPLORE_NEARBY_RADIUS_MILES;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw makeHttpError(400, "nearby_radius_miles must be a valid number.");
  }

  if (
    value < MIN_EXPLORE_NEARBY_RADIUS_MILES ||
    value > MAX_EXPLORE_NEARBY_RADIUS_MILES
  ) {
    throw makeHttpError(
      400,
      `nearby_radius_miles must be between ${MIN_EXPLORE_NEARBY_RADIUS_MILES} and ${MAX_EXPLORE_NEARBY_RADIUS_MILES}.`,
    );
  }

  return value;
}
