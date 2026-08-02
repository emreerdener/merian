import { assertEquals, assertFalse } from "@std/assert";
import type { ExploreSpeciesPostRow } from "./db.ts";
import { prepareExploreSpeciesPostsPage } from "./response.ts";

function makeRow(
  postId: string,
  quality: number | null,
  mediaItems: ExploreSpeciesPostRow["media_items"],
): ExploreSpeciesPostRow {
  return {
    post_id: postId,
    scan_id: crypto.randomUUID(),
    hero_image_url: "https://media.merian.app/hero.webp",
    reference_thumbnail_url: "https://media.merian.app/reference.webp",
    shared_at: "2026-07-14T12:00:00.000Z",
    author_user_id: crypto.randomUUID(),
    author_name: "Test Author",
    species_common_name: "Test Species",
    species_scientific_name: "Testus species",
    location_sharing: "obscured",
    like_count: 0,
    comment_count: 0,
    viewer_has_liked: false,
    is_owned_by_viewer: false,
    media_items: mediaItems,
    image_quality_score: quality,
  };
}

Deno.test("Explore species page preserves media metadata and hides internal quality", () => {
  const imageRow = makeRow(crypto.randomUUID(), 92, [{
    kind: "image",
    url: "https://media.merian.app/image.webp",
    thumbnail_url: "https://media.merian.app/image.webp",
    order_index: 0,
    duration_seconds: null,
    has_audio: false,
  }]);
  const videoRow = makeRow(crypto.randomUUID(), 88, [{
    kind: "video",
    url: "https://media.merian.app/video.mp4",
    thumbnail_url: "https://media.merian.app/video.webp",
    order_index: 0,
    duration_seconds: 5,
    has_audio: true,
  }]);
  const audioRow = makeRow(crypto.randomUUID(), null, [{
    kind: "audio",
    url: "https://media.merian.app/audio.wav",
    thumbnail_url: "https://media.merian.app/spectrogram.webp",
    order_index: 0,
    duration_seconds: 8.5,
    has_audio: true,
  }]);

  const page = prepareExploreSpeciesPostsPage(
    [imageRow, videoRow, audioRow],
    2,
  );

  assertEquals(page.data.map((row) => row.media_items?.[0].kind), [
    "image",
    "video",
  ]);
  assertEquals(
    page.data[0].reference_thumbnail_url,
    "https://media.merian.app/reference.webp",
  );
  assertFalse("image_quality_score" in page.data[0]);
  assertEquals(page.nextCursor, {
    image_quality_score: 88,
    shared_at: videoRow.shared_at,
    post_id: videoRow.post_id,
  });

  const unscoredPage = prepareExploreSpeciesPostsPage([audioRow, imageRow], 1);
  assertEquals(unscoredPage.nextCursor?.image_quality_score, null);
});
