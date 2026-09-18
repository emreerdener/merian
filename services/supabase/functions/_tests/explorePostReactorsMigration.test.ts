import { assertStringIncludes } from "@std/assert";
Deno.test("post reactors migration is guarded, service-only, and filters before unique aggregation", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260918163435_add_explore_post_reactors.sql",
      import.meta.url,
    ),
  );
  for (
    const contract of [
      "internal.require_service_role()",
      "internal.explore_reaction_post(self_id, 'post', target_post_id)",
      "SECURITY DEFINER SET search_path = ''",
      "public.explore_post_likes",
      "public.explore_post_reactions",
      "NOT u.is_shadowbanned",
      "b.blocker_id = self_id",
      "b.blocked_id = self_id",
      "SELECT DISTINCT v.user_id",
      "LIMIT 33",
      "LIMIT 32",
      "LIMIT 2",
      "FROM PUBLIC,anon,authenticated,service_role",
      "TO service_role",
      "internal.privileged_routine_grants",
    ]
  ) assertStringIncludes(sql, contract);
});
