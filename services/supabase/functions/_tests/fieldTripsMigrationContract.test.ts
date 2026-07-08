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
      "type TEXT NOT NULL CHECK",
      "n.type::TEXT AS type",
      "n.type::public.explore_notification_type AS type",
      "AND n.field_trip_publication_id IS NULL",
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
      "ALTER TYPE public.explore_notification_type ADD VALUE IF NOT EXISTS 'field_trip_",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Field Trips v3 must not write to or extend Explore feed/push infrastructure: ${forbidden}`,
    );
  }
});

Deno.test("Field Trips v4 adds curated seasonal challenge contracts", async () => {
  const sql = normalized(
    await migrationSql("20260708051414_field_trips_v4_challenges.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenges",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_participants",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_item_completions",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_badges",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entries",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_items",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_likes",
      "CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_comments",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_challenges_catalog",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_detail",
      "CREATE OR REPLACE FUNCTION public.join_field_trip_challenge",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress",
      "CREATE OR REPLACE FUNCTION public.publish_field_trip_challenge_entry",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_entry_detail",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_hashtags_for_scan",
      "'summer_pollinator_watch'",
      "'neighborhood_night_watch'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trips v4 challenges stay non-competitive and Explore-separated", async () => {
  const sql = normalized(
    await migrationSql("20260708051414_field_trips_v4_challenges.sql"),
  );

  for (
    const fragment of [
      "Challenges are admin-created and never create Explore posts, maps, widgets, APNs, prizes, or leaderboards.",
      "scan_row.timestamp >= p.joined_at",
      "scan_row.timestamp <= c.ends_at",
      "Completion badges for non-competitive Field Trip challenges",
      "suggested_hashtags",
      "ON CONFLICT(participation_id)",
      "new_entry_id UUID",
      "AND s.user_id = self_id",
      "AND s.is_tombstoned = FALSE",
      "AND NOW() <= c.ends_at",
      "public.user_has_visible_field_trip_profile((SELECT auth.uid()), user_id)",
      "RETURN JSONB_BUILD_OBJECT('entry_id', new_entry_id)",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(" entry_id UUID;"),
    "Challenge entry publishing should avoid an entry_id PL/pgSQL variable that collides with item columns",
  );

  for (
    const forbidden of [
      "INSERT INTO public.explore_posts",
      "functions/v1/send-push-notification",
      "CREATE TABLE IF NOT EXISTS public.field_trip_leaderboards",
      "CREATE TABLE IF NOT EXISTS public.field_trip_prizes",
      "CREATE TABLE IF NOT EXISTS public.field_trip_winners",
      "explore_widget",
      "get_explore_map",
      "get_explore_feed_trending",
    ]
  ) {
    assert(
      !sql.toLowerCase().includes(forbidden.toLowerCase()),
      `Field Trips v4 challenges must not create competitive or Explore feed/push infrastructure: ${forbidden}`,
    );
  }
});
