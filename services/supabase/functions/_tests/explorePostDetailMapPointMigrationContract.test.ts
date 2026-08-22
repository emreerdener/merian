import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260822160313_add_explore_post_detail_map_point.sql",
  import.meta.url,
);
const catalogUrl = new URL(
  "../../tests/explore_post_detail_map_point.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("Explore detail map point uses only the post-owned public projection", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "DROP FUNCTION public.get_explore_post_detail(UUID, UUID)",
      "map_point JSONB",
      "post.location_sharing = 'open'",
      "post.public_latitude BETWEEN -90 AND 90",
      "post.public_longitude BETWEEN -180 AND 180",
      "post.public_coordinate_visibility IN ('exact', 'obscured')",
      "'latitude', post.public_latitude",
      "'longitude', post.public_longitude",
      "'coordinate_visibility', post.public_coordinate_visibility",
      "FROM public.explore_projected_post_cards(self_id) AS visible_post",
      "REVOKE ALL ON FUNCTION public.get_explore_post_detail(UUID, UUID) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_explore_post_detail(UUID, UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !/scan\.gps_(?:lat|long)_(?:exact|public)/i.test(sql),
    "Explore detail must never source its map point from scan coordinates.",
  );
});

Deno.test("Explore detail map point catalog fixture locks the caller boundary", async () => {
  const sql = await Deno.readTextFile(catalogUrl);

  assertStringIncludes(sql, "SELECT extensions.plan(4)");
  assertEquals(
    sql.match(/^SELECT extensions.(?:ok|is)\(/gm)?.length,
    4,
    "Explore detail map-point pgTAP plan must match its assertions.",
  );
});
