import { assertEquals, assertThrows } from "@std/assert";
import {
  normalizeImageQualityCursor,
  normalizeSpeciesPostsLimit,
  parseExploreSpeciesPostsRequest,
} from "./request.ts";

const speciesId = "11111111-1111-4111-8111-111111111111";
const postId = "22222222-2222-4222-8222-222222222222";

Deno.test("Explore species posts request parses scored and unscored cursors", () => {
  const scored = parseExploreSpeciesPostsRequest({
    species_id: speciesId,
    limit: 6,
    before_image_quality_score: 92,
    before_shared_at: "2026-07-14T12:00:00.000Z",
    before_post_id: postId,
  });
  assertEquals(scored, {
    speciesId,
    limit: 6,
    beforeImageQualityScore: 92,
    beforeSharedAt: "2026-07-14T12:00:00.000Z",
    beforePostId: postId,
  });

  const unscored = parseExploreSpeciesPostsRequest({
    species_id: speciesId,
    before_shared_at: "2026-07-13T12:00:00.000Z",
    before_post_id: postId,
  });
  assertEquals(unscored.beforeImageQualityScore, null);
  assertEquals(unscored.limit, 30);
});

Deno.test("Explore species posts request rejects partial or invalid cursors", () => {
  assertThrows(
    () =>
      parseExploreSpeciesPostsRequest({
        species_id: speciesId,
        before_shared_at: "2026-07-14T12:00:00.000Z",
      }),
    Error,
    "must be provided together",
  );
  assertThrows(
    () =>
      parseExploreSpeciesPostsRequest({
        species_id: speciesId,
        before_image_quality_score: 80,
      }),
    Error,
    "requires before_shared_at",
  );
  assertThrows(
    () => normalizeImageQualityCursor(101),
    Error,
    "integer from 0 to 100",
  );
});

Deno.test("Explore species posts request validates species UUID and page limit", () => {
  assertThrows(
    () => parseExploreSpeciesPostsRequest({ species_id: "not-a-uuid" }),
    Error,
    "species_id must be a valid UUID",
  );
  assertEquals(normalizeSpeciesPostsLimit(undefined), 30);
  assertEquals(normalizeSpeciesPostsLimit(100), 100);
  assertThrows(
    () => normalizeSpeciesPostsLimit(0),
    Error,
    "integer from 1 to 100",
  );
  assertThrows(
    () => normalizeSpeciesPostsLimit(4.5),
    Error,
    "integer from 1 to 100",
  );
  assertThrows(
    () => normalizeSpeciesPostsLimit(101),
    Error,
    "integer from 1 to 100",
  );
});
