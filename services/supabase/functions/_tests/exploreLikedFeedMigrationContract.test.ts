import { assert, assertEquals, assertStringIncludes } from "@std/assert";

Deno.test("Liked feed migration preserves viewer membership, projection, and cursor boundary", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260912030329_add_explore_liked_feed.sql",
      import.meta.url,
    ),
  )).replaceAll(/\s+/g, " ");
  for (
    const fragment of [
      "ON public.explore_post_likes (user_id, post_id)",
      "SECURITY INVOKER STABLE SET search_path = ''",
      "JOIN public.explore_projected_post_cards(self_id) cards ON cards.post_id = likes.post_id",
      "WHERE likes.user_id = self_id",
      "cards.shared_at >= shared_since",
      "= ANY(requested_species_categories)",
      "filtered_media.kind = ANY(requested_media_types)",
      "cards.shared_at = before_shared_at AND cards.post_id < before_post_id",
      "ORDER BY cards.shared_at DESC, cards.post_id DESC",
      ") FROM PUBLIC, anon, authenticated;",
      ") TO service_role;",
      "NOTIFY pgrst, 'reload schema';",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    sql.indexOf("WHERE likes.user_id = self_id") <
      sql.indexOf("LIMIT GREATEST"),
  );
  assert(sql.indexOf("filtered_media.kind") < sql.indexOf("LIMIT GREATEST"));
  assert(!sql.includes("SECURITY DEFINER"));
});

Deno.test("Liked feed source repair grants only the missing service reads", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260912045555_restore_explore_liked_feed_source_reads.sql",
      import.meta.url,
    ),
  )).replaceAll(/--[^\n]*/g, "").replaceAll(/\s+/g, " ").trim();
  assertEquals(
    sql.split(";").map((statement) => statement.trim()).filter(Boolean),
    [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "GRANT SELECT ON TABLE public.explore_post_likes, public.explore_observation_projection, public.user_blocks TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ],
    "The repair must not widen client access, add writes, or replace invoker routines",
  );
});

Deno.test("Liked feed reference repair adds only the nested helper read", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260912141817_restore_explore_liked_feed_reference_reads.sql",
      import.meta.url,
    ),
  )).replaceAll(/--[^\n]*/g, "").replaceAll(/\s+/g, " ").trim();
  assertEquals(
    sql.split(";").map((statement) => statement.trim()).filter(Boolean),
    [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "GRANT SELECT ON TABLE public.species_reference_images TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ],
    "The repair must add only SELECT and preserve existing caller permissions",
  );
});
