import {
  normalizeExploreMediaTypes,
  normalizeExploreSpeciesCategories,
} from "../_shared/exploreFeedFilters.ts";
import { ExploreMapMediaType, ExploreMapSpeciesCategory } from "./types.ts";

export function normalizeSpeciesCategories(
  value: unknown,
): ExploreMapSpeciesCategory[] {
  return normalizeExploreSpeciesCategories(value);
}

export function normalizeMediaTypes(value: unknown): ExploreMapMediaType[] {
  return normalizeExploreMediaTypes(value);
}
