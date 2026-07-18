import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationsDir = new URL("../../migrations/", import.meta.url);
const fieldTripsFunctionDir = new URL("../field-trips/", import.meta.url);

async function migrationSql(fileName: string): Promise<string> {
  return await Deno.readTextFile(new URL(fileName, migrationsDir));
}

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Field trips migration creates separate progress, publication, like, and comment storage", async () => {
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

Deno.test("Field trips migration preserves privacy and Explore separation contracts", async () => {
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
    "publishing a Field trip must not create a normal Explore post",
  );
  assert(
    !sql.includes("'scan_id', fpi.scan_id"),
    "public Field trip detail should expose publication item ids, not raw scan ids",
  );
});

Deno.test("Field trips seed catalog keeps starter and Pro access distinct", async () => {
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

Deno.test("Field trips catalog keeps Backyard safari in sentence case", async () => {
  const sql = normalized(
    await migrationSql("20260717032701_rename_backyard_safari.sql"),
  );

  for (
    const fragment of [
      "UPDATE public.field_trip_templates",
      "SET title = 'Backyard safari'",
      "WHERE slug = 'backyard_safari'",
      "UPDATE public.field_trip_publications AS publication",
      "AND publication.title = 'Backyard Safari'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Forest Edges placeholder is retired without deleting user history", async () => {
  const sql = normalized(
    await migrationSql("20260717224544_retire_forest_edges_outing.sql"),
  );

  for (
    const fragment of [
      "UPDATE public.field_trip_templates",
      "SET is_active = FALSE",
      "WHERE slug = 'forest_edges'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("DELETE FROM"),
    "Retiring a placeholder must preserve user progress and evidence",
  );
});

Deno.test("Field trips migration avoids reserved SQL parameter names", async () => {
  const sql = normalized(
    await migrationSql("20260708021110_field_trips_v1.sql"),
  );

  const reservedParameterPattern =
    /CREATE OR REPLACE FUNCTION public\.field_trip_[^(]+\([^)]*\b(values|user|order|limit|offset|table|select|where|from|to|group)\s+[A-Z]/i;

  assert(
    !reservedParameterPattern.test(sql),
    "Field trip helper functions should avoid unquoted reserved SQL parameter names",
  );
});

Deno.test("Field trips v2 migration adds guided detail, start, recent trips, and profile pin contracts", async () => {
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

Deno.test("Contextual field trip guides add structured reviewed content without removing legacy tips", async () => {
  const sql = normalized(
    await migrationSql("20260717150222_contextual_outing_objective_guides.sql"),
  );

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS guide_where_to_look TEXT",
      "ADD COLUMN IF NOT EXISTS guide_best_conditions TEXT",
      "ADD COLUMN IF NOT EXISTS guide_what_to_notice TEXT",
      "ADD COLUMN IF NOT EXISTS guide_scan_safely TEXT",
      "'backyard_safari'",
      "'park_pollinators'",
      "'forest_edges'",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_catalog",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail",
      "'guide_tip', fci.guide_tip",
      "'guide', CASE",
      "'where_to_look', fci.guide_where_to_look",
      "'best_conditions', fci.guide_best_conditions",
      "'what_to_notice', fci.guide_what_to_notice",
      "'scan_safely', fci.guide_scan_safely",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("openai") && !sql.includes("anthropic") &&
      !sql.includes("generate_content"),
    "Objective guides must remain reviewed static content with no runtime AI calls",
  );
});

Deno.test("Private field trip checklist payloads expose the completing scan id", async () => {
  const sql = normalized(
    await migrationSql(
      "20260718043218_expose_field_trip_completion_scan_ids.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_field_trip_catalog",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail",
      "'completed_scan_id', ufc.scan_id",
      "LEFT JOIN public.user_field_trip_item_completions ufc",
      "uft.user_id = self_id",
      "REVOKE ALL ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_catalog(UUID, TEXT, INTEGER) TO service_role",
      "REVOKE ALL ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    (sql.match(/'completed_scan_id', ufc\.scan_id/g) ?? []).length === 2,
    "catalog and template detail must both carry the completing scan id",
  );
  assert(
    !sql.includes("field_trip_publication_items"),
    "completion scan ids must remain out of public Field trip snapshots",
  );
});

Deno.test("Initial Field trip capture context is focused, ordered, and service-role only", async () => {
  const sql = normalized(
    await migrationSql("20260717195751_active_outing_capture_context.sql"),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_field_trip_capture_context( self_id UUID )",
      "SECURITY INVOKER",
      "SET search_path = ''",
      "CREATE INDEX IF NOT EXISTS idx_user_field_trips_capture_context ON public.user_field_trips(user_id, started_at DESC) WHERE completed_at IS NULL AND hidden_at IS NULL",
      "CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_participants_outing ON public.field_trip_challenge_participants(user_field_trip_id)",
      "uft.completed_at IS NULL",
      "uft.hidden_at IS NULL",
      "fl.level_number = uft.current_level_number",
      "t.is_pro_only = FALSE OR viewer.is_pro OR t.is_rotating_free = TRUE",
      "FILTER (WHERE completion.id IS NULL)",
      "ORDER BY item.sort_order, item.id",
      "ORDER BY row.last_engaged_at DESC, row.user_field_trip_id",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM PUBLIC",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM anon",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_capture_context(UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  for (
    const privateEvidence of [
      "'scan_id'",
      "'media'",
      "'location'",
      "'field_notes'",
      "'common_name'",
      "'scientific_name'",
    ]
  ) {
    assert(
      !sql.includes(privateEvidence),
      `Capture context must not return private evidence: ${privateEvidence}`,
    );
  }
});

Deno.test("Capture context keeps a standard field trip after Seasonal Challenge join", async () => {
  const sql = normalized(
    await migrationSql(
      "20260717213641_preserve_standard_outings_in_capture_context.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_field_trip_capture_context( self_id UUID )",
      "SECURITY INVOKER",
      "SET search_path = ''",
      "FROM public.user_field_trips uft",
      "LEFT JOIN public.user_field_trip_item_completions completion ON completion.user_field_trip_id = uft.id",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM PUBLIC",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM anon",
      "REVOKE ALL ON FUNCTION public.get_field_trip_capture_context(UUID) FROM authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_capture_context(UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("field_trip_challenge_participants") &&
      !sql.includes("field_trip_challenge_item_completions"),
    "Capture context must keep the standard field trip and ignore challenge-specific progress",
  );
});

Deno.test("Field trip capture context Edge action always uses the verified user", async () => {
  const index = normalized(
    await Deno.readTextFile(new URL("index.ts", fieldTripsFunctionDir)),
  );
  const db = normalized(
    await Deno.readTextFile(new URL("db.ts", fieldTripsFunctionDir)),
  );

  assertStringIncludes(index, '| "capture_context"');
  assertStringIncludes(
    index,
    'case "capture_context": { const data = await fetchFieldTripCaptureContext( user.id, supabaseAdmin',
  );
  assertStringIncludes(
    db,
    'supabaseAdmin.rpc( "get_field_trip_capture_context", { self_id: userId }',
  );
  assert(
    !index.includes("body.self_id") && !index.includes("body.user_id"),
    "Capture context must not accept an account id from the request body",
  );
});

Deno.test("Field trips v2 keeps published trips out of Explore feed infrastructure", async () => {
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
      `Field trips v2 must not write to or extend normal Explore feed infrastructure: ${forbidden}`,
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

Deno.test("Field trips v3 adds community feed ranking and compatibility contracts", async () => {
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

Deno.test("Field trips v3 activity is in-app only and does not extend Explore feed push surfaces", async () => {
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
      `Field trips v3 must not write to or extend Explore feed/push infrastructure: ${forbidden}`,
    );
  }
});

Deno.test("Field trips v4 adds curated seasonal challenge contracts", async () => {
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

Deno.test("Field trips v4 challenges stay non-competitive and Explore-separated", async () => {
  const sql = normalized(
    await migrationSql("20260708051414_field_trips_v4_challenges.sql"),
  );

  for (
    const fragment of [
      "Challenges are admin-created and never create Explore posts, maps, widgets, APNs, prizes, or leaderboards.",
      "scan_row.timestamp >= p.joined_at",
      "scan_row.timestamp <= c.ends_at",
      "Completion badges for non-competitive",
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
      `Field trips v4 challenges must not create competitive or Explore feed/push infrastructure: ${forbidden}`,
    );
  }
});
