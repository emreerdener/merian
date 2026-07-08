import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationsDir = new URL("../../migrations/", import.meta.url);

async function migrationSql(fileName: string): Promise<string> {
  return await Deno.readTextFile(new URL(fileName, migrationsDir));
}

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Field Trips migration creates separate progress, publication, like, and comment storage", async () => {
  const sql = normalized(
    await migrationSql("20260708021110_field_trips_v1.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.field_trip_templates",
      "CREATE TABLE IF NOT EXISTS public.field_trip_levels",
      "CREATE TABLE IF NOT EXISTS public.field_trip_checklist_items",
      "CREATE TABLE IF NOT EXISTS public.user_field_trips",
      "CREATE TABLE IF NOT EXISTS public.user_field_trip_item_completions",
      "CREATE TABLE IF NOT EXISTS public.field_trip_publications",
      "CREATE TABLE IF NOT EXISTS public.field_trip_publication_items",
      "CREATE TABLE IF NOT EXISTS public.field_trip_publication_likes",
      "CREATE TABLE IF NOT EXISTS public.field_trip_publication_comments",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress",
      "CREATE OR REPLACE FUNCTION public.publish_field_trip",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_comments",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trips migration preserves privacy and Explore separation contracts", async () => {
  const sql = normalized(
    await migrationSql("20260708021110_field_trips_v1.sql"),
  );

  for (
    const fragment of [
      "Publishing here does not create Explore posts, map points, or Explore notifications.",
      "public.user_has_visible_field_trip_profile(self_id, target_author_user_id)",
      "public.can_view_field_trip_publication(auth.uid(), id)",
      "s.image_storage_urls[1]",
      "'publication_item_id', fpi.id",
      "'hero_image_url', fpi.hero_image_url",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("INSERT INTO public.explore_posts"),
    "publishing a Field Trip must not create a normal Explore post",
  );
  assert(
    !sql.includes("'scan_id', fpi.scan_id"),
    "public Field Trip detail should expose publication item ids, not raw scan ids",
  );
});

Deno.test("Field Trips seed catalog keeps starter and Pro access distinct", async () => {
  const sql = normalized(
    await migrationSql("20260708021110_field_trips_v1.sql"),
  );

  for (
    const fragment of [
      "'backyard_safari'",
      "'park_pollinators'",
      "'forest_edges'",
      "'Backyard Safari'",
      "'Park Pollinators'",
      "'Forest Edges'",
      "'Felis catus'",
      "'Aves'",
      "'Arachnida'",
      "TRUE, FALSE, 30",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trips migration avoids reserved SQL parameter names", async () => {
  const sql = normalized(
    await migrationSql("20260708021110_field_trips_v1.sql"),
  );

  const reservedParameterPattern =
    /CREATE OR REPLACE FUNCTION public\.field_trip_[^(]+\([^)]*\b(values|user|order|limit|offset|table|select|where|from|to|group)\s+[A-Z]/i;

  assert(
    !reservedParameterPattern.test(sql),
    "Field Trip helper functions should avoid unquoted reserved SQL parameter names",
  );
});

Deno.test("Field Trips v2 migration adds guided detail, start, recent trips, and profile pin contracts", async () => {
  const sql = normalized(
    await migrationSql("20260708033451_field_trips_v2.sql"),
  );

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS cover_image_url TEXT",
      "ADD COLUMN IF NOT EXISTS estimated_duration_minutes INTEGER",
      "ADD COLUMN IF NOT EXISTS guide_where_to_look TEXT",
      "ADD COLUMN IF NOT EXISTS guide_why_it_matters TEXT",
      "ADD COLUMN IF NOT EXISTS guide_safety_ethics TEXT",
      "ADD COLUMN IF NOT EXISTS guide_tip TEXT",
      "ADD COLUMN IF NOT EXISTS profile_pin_position INTEGER",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail",
      "CREATE OR REPLACE FUNCTION public.start_field_trip",
      "CREATE OR REPLACE FUNCTION public.get_recent_field_trip_publications",
      "CREATE OR REPLACE FUNCTION public.set_field_trip_pinned_publications",
      "GRANT EXECUTE ON FUNCTION public.start_field_trip(UUID, UUID) TO authenticated",
      "ORDER BY t.region_rank, t.sort_order, t.title",
      "preferred_count < resolved_limit",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trips v2 keeps published trips out of Explore feed infrastructure", async () => {
  const sql = normalized(
    await migrationSql("20260708033451_field_trips_v2.sql"),
  );

  for (
    const forbidden of [
      "INSERT INTO public.explore_posts",
      "explore_post_notifications",
      "get_explore_feed",
      "get_explore_feed_following",
      "get_explore_feed_trending",
      "get_explore_feed_nearby",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Field Trips v2 must not write to or extend normal Explore feed infrastructure: ${forbidden}`,
    );
  }

  assertStringIncludes(
    sql,
    "ORDER BY ftp.published_at DESC, ftp.id DESC",
  );
  assertStringIncludes(
    sql,
    "OR (ftp.published_at, ftp.id) < (before_published_at, before_publication_id)",
  );
});

Deno.test("Field Trips v3 adds community feed ranking and compatibility contracts", async () => {
  const sql = normalized(
    await migrationSql("20260708042713_field_trips_v3_community.sql"),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_field_trip_community_publications",
      "mode TEXT DEFAULT 'smart'",
      "target_template_id UUID DEFAULT NULL",
      "before_rank_bucket INTEGER DEFAULT NULL",
      "'field_trip_comment'",
      "'field_trip_reply'",
      "'field_trip_followed_publication'",
      "'rank_bucket', rank_bucket",
      "'community_reason', community_reason",
      "'viewer_is_following_author', viewer_is_following_author",
      "rank_bucket ASC, published_at DESC, publication_id DESC",
      "CREATE OR REPLACE FUNCTION public.get_recent_field_trip_publications",
      "'recent'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trips v3 activity is in-app only and does not extend Explore feed push surfaces", async () => {
  const sql = normalized(
    await migrationSql("20260708042713_field_trips_v3_community.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.field_trip_activity_notifications",
      "public.get_explore_notifications",
      "field_trip_publication_id UUID",
      "public.get_unread_explore_notification_count",
      "public.mark_explore_notifications_read",
      "public.trg_field_trip_activity_user_blocks_cleanup",
      "These rows never fan out to APNs, widgets, Explore feed cards, map rows, or explore_posts.",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  for (
    const forbidden of [
      "INSERT INTO public.explore_posts",
      "INSERT INTO public.explore_post_notifications",
      "functions/v1/send-push-notification",
      "explore_widget",
      "get_explore_feed_nearby",
      "get_explore_map",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Field Trips v3 must not write to or extend Explore feed/push infrastructure: ${forbidden}`,
    );
  }
});
