import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildExploreMapPayload } from "./cluster.ts";
import { ExploreMapPostRow } from "./types.ts";

function makeRow(
  id: string,
  latitude: number,
  longitude: number,
): ExploreMapPostRow {
  return {
    post_id: id,
    scan_id: `scan-${id}`,
    latitude,
    longitude,
    coordinate_visibility: "exact",
    hero_image_url: "https://example.com/image.webp",
    shared_at: "2026-04-28T00:00:00Z",
    author_user_id: "author-1",
    author_name: "Explorer",
    author_avatar_url: null,
    species_common_name: "Mushroom",
    species_scientific_name: "Fungus testus",
    public_location_label: "Austin, TX",
    location_sharing: "open",
    time_of_day: null,
    current_month: null,
    weather_condition: null,
    weather_temperature_f: null,
    like_count: 0,
    comment_count: 0,
    viewer_has_liked: false,
    is_owned_by_viewer: false,
  };
}

Deno.test("buildExploreMapPayload returns posts when the result set is small", () => {
  const payload = buildExploreMapPayload(
    [
      makeRow("1", 30.2672, -97.7431),
      makeRow("2", 30.2678, -97.7428),
    ],
    12,
  );

  assertEquals(payload.mode, "posts");
  assertEquals(payload.posts.length, 2);
  assertEquals(payload.clusters.length, 0);
  assertEquals(payload.visible_count, 2);
});

Deno.test("buildExploreMapPayload returns clusters when points are dense at lower zoom", () => {
  const rows = [
    makeRow("1", 30.2672, -97.7431),
    makeRow("2", 30.2673, -97.7432),
    makeRow("3", 30.2674, -97.7430),
    makeRow("4", 30.2675, -97.7429),
    makeRow("5", 30.2676, -97.7428),
  ];

  const payload = buildExploreMapPayload(
    Array.from({ length: 10 }).flatMap((_, index) =>
      rows.map((row) => ({
        ...row,
        post_id: `${row.post_id}-${index}`,
        scan_id: `${row.scan_id}-${index}`,
      }))
    ),
    6,
  );

  assertEquals(payload.mode, "clusters");
  assertEquals(payload.posts.length, 0);
  assertEquals(payload.clusters.length > 0, true);
  assertEquals(payload.visible_count, 50);
});
