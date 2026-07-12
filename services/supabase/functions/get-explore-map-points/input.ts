import { ExploreMapMediaType, ExploreMapSpeciesCategory } from "./types.ts";

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

const ALLOWED_MEDIA_TYPES = new Set<ExploreMapMediaType>([
  "image",
  "video",
  "audio",
]);

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

export function normalizeSpeciesCategories(
  value: unknown,
): ExploreMapSpeciesCategory[] {
  return normalizeStringFilters(value, ALLOWED_SPECIES_CATEGORIES);
}

export function normalizeMediaTypes(value: unknown): ExploreMapMediaType[] {
  return normalizeStringFilters(value, ALLOWED_MEDIA_TYPES);
}
