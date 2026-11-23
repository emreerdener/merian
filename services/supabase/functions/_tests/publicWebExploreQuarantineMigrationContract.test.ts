import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261113222835_quarantine_public_web_explore.sql",
    import.meta.url,
  ),
);
Deno.test("website quarantine applies to every public reader without changing native report preferences", () => {
  for (
    const fn of [
      "get_public_web_explore_posts(",
      "get_public_web_explore_posts_page(",
      "get_public_web_explore_post_detail(",
    ]
  ) {
    assertStringIncludes(sql, `CREATE OR REPLACE FUNCTION public.${fn}`);
  }
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.explore_projected_post_cards",
    ),
  );
  for (
    const value of [
      "review.status IN ('open', 'in_review')",
      "review.case_type = 'post'",
      "review.case_type = 'identification'",
      "internal.require_service_role()",
      "cardinality(p_post_ids) NOT BETWEEN 1 AND 128",
      "array_position(p_post_ids, NULL)",
      "public.explore_projected_post_cards(NULL::UUID)",
      "FROM PUBLIC,anon,authenticated,service_role",
      "public.get_public_web_explore_visibility(uuid[])",
    ]
  ) assertStringIncludes(sql, value);
});
