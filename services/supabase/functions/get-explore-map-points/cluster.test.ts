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
    pet_identification: null,
    taxonomy_kingdom: "Fungi",
    taxonomy_class: "Agaricomycetes",
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

function withMedia(
  row: ExploreMapPostRow,
  kinds: Array<"image" | "video" | "audio">,
): ExploreMapPostRow {
  return {
    ...row,
    media_items: kinds.map((kind, index) => ({
      kind,
      url: `https://example.com/${row.post_id}-${kind}`,
      thumbnail_url: kind === "audio"
        ? null
        : `https://example.com/${row.post_id}-${kind}.webp`,
      order_index: index,
      duration_seconds: kind === "image" ? null : 4,
      has_audio: kind !== "image",
    })),
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

Deno.test("buildExploreMapPayload returns dynamic category counts before filtering", () => {
  const rows = [
    makeRow("fungus", 30.2672, -97.7431),
    {
      ...makeRow("bird", 30.2673, -97.7432),
      taxonomy_kingdom: "Animalia",
      taxonomy_class: "Aves",
    },
    {
      ...makeRow("insect", 30.2674, -97.7433),
      taxonomy_kingdom: "Animalia",
      taxonomy_class: "Insecta",
    },
  ];

  const payload = buildExploreMapPayload(rows, 12, ["birds"]);

  assertEquals(payload.mode, "posts");
  assertEquals(payload.visible_count, 1);
  assertEquals(payload.posts.map((post) => post.post_id), ["bird"]);
  assertEquals(payload.category_counts, [
    { category: "birds", count: 1 },
    { category: "fungi", count: 1 },
    { category: "insects", count: 1 },
  ]);
});

Deno.test("media filters match any selected attached media type", () => {
  const image = withMedia(makeRow("image", 30.2672, -97.7431), ["image"]);
  const video = withMedia(makeRow("video", 30.2673, -97.7432), ["video"]);
  const mixed = withMedia(makeRow("mixed", 30.2674, -97.7433), [
    "image",
    "audio",
  ]);

  const payload = buildExploreMapPayload(
    [image, video, mixed],
    12,
    [],
    ["video", "audio"],
  );

  assertEquals(payload.posts.map((post) => post.post_id), ["video", "mixed"]);
  assertEquals(payload.visible_count, 2);
  assertEquals(payload.media_type_counts, [
    { media_type: "image", count: 2 },
    { media_type: "video", count: 1 },
    { media_type: "audio", count: 1 },
  ]);
});

Deno.test("species and media filters intersect while facet counts cross-filter", () => {
  const fungusImage = withMedia(makeRow("fungus-image", 30.2672, -97.7431), [
    "image",
  ]);
  const fungusAudio = withMedia(makeRow("fungus-audio", 30.2673, -97.7432), [
    "audio",
  ]);
  const birdAudio = withMedia({
    ...makeRow("bird-audio", 30.2674, -97.7433),
    taxonomy_kingdom: "Animalia",
    taxonomy_class: "Aves",
  }, ["audio"]);

  const payload = buildExploreMapPayload(
    [fungusImage, fungusAudio, birdAudio],
    12,
    ["fungi"],
    ["audio"],
  );

  assertEquals(payload.posts.map((post) => post.post_id), ["fungus-audio"]);
  assertEquals(payload.category_counts, [
    { category: "birds", count: 1 },
    { category: "fungi", count: 1 },
  ]);
  assertEquals(payload.media_type_counts, [
    { media_type: "image", count: 1 },
    { media_type: "audio", count: 1 },
  ]);
});

Deno.test("legacy hero-only rows classify as images", () => {
  const legacy = makeRow("legacy", 30.2672, -97.7431);
  const payload = buildExploreMapPayload([legacy], 12, [], ["image"]);

  assertEquals(payload.posts.map((post) => post.post_id), ["legacy"]);
  assertEquals(payload.media_type_counts, [{ media_type: "image", count: 1 }]);
});

Deno.test("media filters are applied before clustering", () => {
  const rows = Array.from({ length: 50 }, (_, index) =>
    withMedia(
      makeRow(`${index}`, 30.2672 + (index * 0.00001), -97.7431),
      [index < 45 ? "image" : "audio"],
    ));

  const payload = buildExploreMapPayload(rows, 6, [], ["audio"]);

  assertEquals(payload.mode, "posts");
  assertEquals(payload.visible_count, 5);
  assertEquals(payload.posts.length, 5);
  assertEquals(payload.clusters, []);
});
