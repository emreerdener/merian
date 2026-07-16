import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  DEFAULT_EXPLORE_NEARBY_RADIUS_MILES,
  normalizeExploreMediaTypes,
  normalizeExploreNearbyRadiusMiles,
  normalizeExploreSpeciesCategories,
} from "./exploreFeedFilters.ts";

Deno.test("Explore filters normalize shared species and media values", () => {
  assertEquals(
    normalizeExploreSpeciesCategories([" Birds ", "birds", "fungi", 42]),
    ["birds", "fungi"],
  );
  assertEquals(
    normalizeExploreMediaTypes([" Audio ", "audio", "video", "document"]),
    ["audio", "video"],
  );
});

Deno.test("Explore nearby radius defaults and enforces the public bound", () => {
  assertEquals(
    normalizeExploreNearbyRadiusMiles(undefined),
    DEFAULT_EXPLORE_NEARBY_RADIUS_MILES,
  );
  assertEquals(normalizeExploreNearbyRadiusMiles(25), 25);

  const error = assertThrows(
    () => normalizeExploreNearbyRadiusMiles(101),
    Error,
    "nearby_radius_miles must be between 1 and 100",
  ) as Error & { status?: number };
  assertEquals(error.status, 400);
});
