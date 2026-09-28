import { assertEquals, assertStringIncludes } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260927220537_hide_reported_explore_posts.sql",
    import.meta.url,
  ),
);
Deno.test("reported visibility migration guards direct readers without exposing report records", () => {
  for (
    const boundary of [
      "public.explore_projected_post_cards(uuid)",
      "public.get_community_identification_feed(",
      "public.get_community_identification_detail(",
      "public.get_community_identification_activity(",
      "public.get_explore_comments(",
      "public.get_explore_comment_replies(",
      "public.get_explore_notifications(",
      "public.get_explore_notifications_with_reactions(",
      "auth.uid() IS DISTINCT FROM self_id",
      "PERFORM internal.require_service_role()",
      "public.viewer_has_reported_explore_post(uuid,uuid)",
      "SET search_path = ''",
      "idx_explore_post_reports_reporter_post",
      "source.image_url = btrim(candidate_url)",
      "btrim(candidate_url) = ANY(s.image_storage_urls)",
      "m.thumbnail_url",
    ]
  ) assertStringIncludes(migration, boundary);
  assertEquals(
    migration.includes("GRANT SELECT ON public.explore_post_reports"),
    false,
  );
  assertEquals(migration.includes("r.status"), false);
});
