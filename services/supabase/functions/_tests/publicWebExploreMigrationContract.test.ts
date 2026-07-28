import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationUrl = new URL(
  "../../migrations/20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql",
  import.meta.url,
);
const migration = await Deno.readTextFile(migrationUrl);
const repairMigrationUrl = new URL(
  "../../migrations/20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql",
  import.meta.url,
);
const repairMigration = await Deno.readTextFile(repairMigrationUrl);

Deno.test("public web Explore uses a fixed-viewer service-only projection", () => {
  for (
    const expected of [
      "CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts",
      "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail",
      "SECURITY DEFINER",
      "SET search_path = ''",
      "SET statement_timeout = '10s'",
      "PERFORM internal.require_service_role()",
      "public.explore_projected_post_cards(NULL::UUID)",
      "public.get_explore_post_detail(\n        NULL::UUID",
      "p_max_limit NOT BETWEEN 1 AND 48",
      "author.public_username",
      "author.subscription_tier = 'pro'",
      "0::INTEGER",
      "FALSE",
      "REVOKE ALL ON FUNCTION public.get_public_web_explore_posts(UUID, INTEGER)",
      "REVOKE ALL ON FUNCTION public.get_public_web_explore_post_detail(UUID)",
      "FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_public_web_explore_posts(UUID, INTEGER)",
      "GRANT EXECUTE ON FUNCTION public.get_public_web_explore_post_detail(UUID)",
      "TO service_role",
      "public.get_public_web_explore_posts(uuid,integer)",
      "public.get_public_web_explore_post_detail(uuid)",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }

  const postsStart = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts",
  );
  const detailStart = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail",
  );
  const postsFunction = migration.slice(postsStart, detailStart);
  assertEquals(postsFunction.includes("self_id"), false);
  assertEquals(postsFunction.includes("auth.uid()"), false);
  assertEquals(postsFunction.includes("cards.like_count"), false);
  assertEquals(postsFunction.includes("cards.comment_count"), false);
  assertEquals(postsFunction.includes("GRANT SELECT"), false);
});

Deno.test("public web Explore detail is independently canonical and page fetch is atomic", () => {
  for (
    const expected of [
      "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail",
      "INNER JOIN public.explore_projected_post_cards(",
      "NULL::UUID",
      "ON canonical_post.post_id = detail.post_id",
      "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_page",
      "post_payload JSONB",
      "detail_payload JSONB",
      "FROM public.get_public_web_explore_posts(",
      "LEFT JOIN LATERAL public.get_public_web_explore_post_detail(",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.get_public_web_explore_post_page(UUID)",
      "GRANT EXECUTE ON FUNCTION public.get_public_web_explore_post_page(UUID)",
      "TO service_role",
      "public.get_public_web_explore_post_page(uuid)",
    ]
  ) {
    assertStringIncludes(repairMigration, expected);
  }

  const detailStart = repairMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail",
  );
  const pageStart = repairMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_page",
  );
  const detailFunction = repairMigration.slice(detailStart, pageStart);
  assertStringIncludes(detailFunction, "public.get_explore_post_detail(");
  assertStringIncludes(
    detailFunction,
    "public.explore_projected_post_cards(",
  );
  assertEquals(detailFunction.includes("auth.uid()"), false);
  assertEquals(repairMigration.includes("GRANT SELECT"), false);
});
