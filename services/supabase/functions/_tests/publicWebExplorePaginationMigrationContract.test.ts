import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261108062742_public_web_explore_pagination.sql",
    import.meta.url,
  ),
);
Deno.test("public canvas pagination preserves canonical anonymous projection and service ACL", () => {
  for (
    const text of [
      "internal.require_service_role()",
      "SET search_path TO ''",
      "SET statement_timeout TO '10s'",
      "p_max_limit NOT BETWEEN 1 AND 48",
      "(p_before_shared_at IS NULL) <> (p_before_post_id IS NULL)",
      "pg_catalog.isfinite(p_before_shared_at)",
      "public.explore_projected_post_cards(NULL::UUID)",
      "(cards.shared_at, cards.post_id) < (p_before_shared_at, p_before_post_id)",
      "ORDER BY cards.shared_at DESC, cards.post_id DESC",
      "LIMIT p_max_limit + 1",
      "FROM PUBLIC,anon,authenticated,service_role",
      "TO service_role",
      "internal.privileged_routine_grants",
      "public.get_public_web_explore_posts_page(integer,timestamp with time zone,uuid)",
    ]
  ) assertStringIncludes(sql, text);
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts(",
    ),
  );
});
