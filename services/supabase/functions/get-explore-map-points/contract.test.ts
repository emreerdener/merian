import { assertEquals } from "@std/assert";
import { normalizeExploreMapRows } from "./contract.ts";
import { normalizeMediaTypes, normalizeSpeciesCategories } from "./input.ts";
import type { ExploreMapPostRow } from "./types.ts";

function makeRow(
  overrides: Partial<ExploreMapPostRow> = {},
): ExploreMapPostRow {
  return {
    post_id: "post-1",
    scan_id: "scan-1",
    latitude: 30.2672,
    longitude: -97.7431,
    coordinate_visibility: "exact",
    hero_image_url: "https://example.com/image.webp",
    shared_at: "2026-07-11T20:00:00Z",
    author_user_id: "author-1",
    author_name: "Explorer",
    species_common_name: "Northern Cardinal",
    species_scientific_name: "Cardinalis cardinalis",
    location_sharing: "open",
    like_count: 0,
    comment_count: 0,
    viewer_has_liked: false,
    is_owned_by_viewer: false,
    ...overrides,
  };
}

Deno.test("map contract preserves an image hero URL", () => {
  const [row] = normalizeExploreMapRows([makeRow()]);
  assertEquals(row.hero_image_url, "https://example.com/image.webp");
});

Deno.test("map contract uses a video thumbnail when the hero is null", () => {
  const [row] = normalizeExploreMapRows([makeRow({
    hero_image_url: null,
    media_items: [{
      kind: "video",
      url: "https://example.com/video.mp4",
      thumbnail_url: "https://example.com/video.webp",
      order_index: 0,
      duration_seconds: 4.5,
      has_audio: true,
    }],
  })]);
  assertEquals(row.hero_image_url, "https://example.com/video.webp");
});

Deno.test("map contract uses a species reference for audio-only media", () => {
  const [row] = normalizeExploreMapRows([makeRow({
    hero_image_url: null,
    reference_thumbnail_url: "https://example.com/cardinal.webp",
    media_items: [{
      kind: "audio",
      url: "https://example.com/cardinal.wav",
      thumbnail_url: null,
      order_index: 0,
      duration_seconds: 8,
      has_audio: true,
    }],
  })]);
  assertEquals(row.hero_image_url, "https://example.com/cardinal.webp");
  assertEquals(row.media_items?.[0].kind, "audio");
});

Deno.test("map contract emits an empty string when all posters are missing", () => {
  const [row] = normalizeExploreMapRows([makeRow({
    hero_image_url: undefined,
    reference_thumbnail_url: null,
  })]);
  assertEquals(row.hero_image_url, "");
  assertEquals(row.reference_thumbnail_url, null);
});

Deno.test("one malformed row does not remove valid map rows", () => {
  const rows = normalizeExploreMapRows([
    makeRow({ post_id: "valid" }),
    makeRow({ post_id: "media-only", hero_image_url: null }),
  ]);
  assertEquals(rows.map((row) => row.post_id), ["valid", "media-only"]);
  assertEquals(rows[1].hero_image_url, "");
});

Deno.test("map filters normalize allowed values and remove duplicates", () => {
  assertEquals(
    normalizeSpeciesCategories([" Birds ", "birds", "unknown", 42]),
    ["birds"],
  );
  assertEquals(
    normalizeMediaTypes([" Video ", "video", "audio", "document", null]),
    ["video", "audio"],
  );
  assertEquals(normalizeMediaTypes("video"), []);
});
