import { assertEquals } from "@std/assert";
import type { ExploreAuthorPostRow } from "./db.ts";
import { prepareExploreAuthorPostsPage } from "./response.ts";

function makeRow(postId: string, sharedAt: string): ExploreAuthorPostRow {
  return {
    post_id: postId,
    scan_id: crypto.randomUUID(),
    hero_image_url: "https://media.merian.app/hero.webp",
    shared_at: sharedAt,
    author_user_id: crypto.randomUUID(),
    author_name: "Test Author",
    species_common_name: "Test Species",
    species_scientific_name: "Testus species",
    location_sharing: "obscured",
    like_count: 0,
    comment_count: 0,
    viewer_has_liked: false,
    is_owned_by_viewer: false,
  };
}

Deno.test("Explore author posts page returns an explicit continuation cursor", () => {
  const rows = [
    makeRow(
      "00000000-0000-0000-0000-000000000111",
      "2026-07-26T12:03:00.000Z",
    ),
    makeRow(
      "00000000-0000-0000-0000-000000000222",
      "2026-07-26T12:02:00.000Z",
    ),
    makeRow(
      "00000000-0000-0000-0000-000000000333",
      "2026-07-26T12:01:00.000Z",
    ),
  ];

  const page = prepareExploreAuthorPostsPage(rows, 2);

  assertEquals(page.data.map((row) => row.post_id), [
    "00000000-0000-0000-0000-000000000111",
    "00000000-0000-0000-0000-000000000222",
  ]);
  assertEquals(page.nextCursor, {
    before_shared_at: "2026-07-26T12:02:00.000Z",
    before_post_id: "00000000-0000-0000-0000-000000000222",
  });
});

Deno.test("Explore author posts page omits the cursor at the end", () => {
  const row = makeRow(
    "00000000-0000-0000-0000-000000000111",
    "2026-07-26T12:03:00.000Z",
  );

  const page = prepareExploreAuthorPostsPage([row], 2);

  assertEquals(page.data, [row]);
  assertEquals(page.nextCursor, null);
});
