import { assert, assertEquals, assertStringIncludes } from "@std/assert";

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

Deno.test("Field Trip hardening makes progress transactional and RPCs service-role only", async () => {
  const sql = normalized(
    await migrationSql("20260722064704_harden_atomic_field_trip_progress.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.field_trip_scan_progress_receipts",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_atomic",
      "field_trip_updates := public.apply_field_trip_scan_progress_v2",
      "challenge_updates := public.apply_field_trip_challenge_scan_progress",
      "CREATE OR REPLACE FUNCTION public.apply_ingested_scan_field_trip_progress",
      "AFTER INSERT ON public.scans",
      "AFTER UPDATE OF species_id, confirmed_species_id, is_biological_subject, is_tombstoned, timestamp ON public.scans",
      "CREATE OR REPLACE FUNCTION public.set_field_trip_pinned_publications",
      "normalized_publication_ids UUID[] := ARRAY[]::UUID[]",
      "SET search_path = ''",
      "AND procedure.prokind = 'f'",
      "REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION %s TO service_role",
      "created_publication_id, fci.id",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Field Trip confidence policy blocks weak matches and repairs prior credit", async () => {
  const sql = normalized(
    await migrationSql(
      "20260730023042_gate_field_trip_progress_by_confidence.sql",
    ),
  );

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '5min'",
      "CREATE OR REPLACE FUNCTION public.field_trip_scan_identification_is_eligible",
      "confirmed_species_id IS NOT NULL OR COALESCE(user_confirmed_identification, FALSE)",
      "WHEN LOWER(BTRIM(COALESCE(inference_tier, ''))) = 'pro' THEN 0.65 ELSE 0.75",
      "CREATE OR REPLACE FUNCTION public.remove_ineligible_field_trip_scan_progress",
      "CREATE OR REPLACE FUNCTION public.remove_ineligible_field_trip_challenge_scan_progress",
      "RENAME TO apply_field_trip_scan_progress_v2_unchecked",
      "RENAME TO apply_field_trip_challenge_scan_progress_unchecked",
      "IF identification_is_eligible IS NOT TRUE THEN RETURN public.remove_ineligible_field_trip_scan_progress",
      "IF identification_is_eligible IS NOT TRUE THEN RETURN public.remove_ineligible_field_trip_challenge_scan_progress",
      "'ai_confidence_score', scan.ai_confidence_score",
      "'inference_tier', scan.inference_tier",
      "'user_confirmed_identification', scan.user_confirmed_identification",
      "effective_preferred_user_field_trip_id := existing_receipt.preferred_user_field_trip_id",
      "PERFORM internal.require_service_role()",
      "GRANT EXECUTE ON FUNCTION public.apply_field_trip_scan_progress_atomic",
      "AFTER UPDATE OF species_id, confirmed_species_id, ai_confidence_score, inference_tier, user_confirmed_identification",
      "CREATE TEMP TABLE invalid_confidence_standard_completions",
      "CREATE TEMP TABLE invalid_confidence_challenge_completions",
      "DELETE FROM public.user_field_trip_item_completions",
      "DELETE FROM public.field_trip_challenge_item_completions",
      "completed_at = NULL",
      "badge_awarded_at = NULL",
      "UPDATE public.field_trip_publications",
      "UPDATE public.field_trip_challenge_entries",
      "PERFORM public.apply_field_trip_scan_progress_atomic",
      "Weak, unreviewed Field Trip progress remains after confidence repair",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "DELETE FROM public.field_trip_scan_goal_preferences",
    ),
    "Weak scans must retain their selected Capture goal for later confirmation",
  );
});

Deno.test("Park Pollinators excludes ants from the Bee or wasp goal and repairs prior credit", async () => {
  const sql = normalized(
    await migrationSql("20260722195453_exclude_ants_from_bee_wasp_goal.sql"),
  );

  for (
    const fragment of [
      "'taxonomy_excluding_family'",
      "taxonomy_family = 'Formicidae'",
      "template.slug = 'park_pollinators'",
      "item.prompt = 'Bee or wasp'",
      "DELETE FROM public.user_field_trip_item_completions",
      "DELETE FROM public.field_trip_challenge_item_completions",
      "DELETE FROM public.field_trip_scan_progress_receipts",
      "completed_at = NULL",
      "badge_awarded_at = NULL",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Backyard Safari and Park Pollinators omit optional why-it-matters guidance", async () => {
  const sql = normalized(
    await migrationSql(
      "20260727030926_hide_why_it_matters_for_backyard_and_pollinators.sql",
    ),
  );

  for (
    const fragment of [
      "SET guide_why_it_matters = NULL",
      "slug IN ('backyard_safari', 'park_pollinators')",
      "guide_why_it_matters IS NOT NULL",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Active Field Trip goals use narrow, verifiable compound rules", async () => {
  const sql = normalized(
    await migrationSql("20260722211636_tighten_field_trip_goal_matching.sql"),
  );

  for (
    const fragment of [
      "'taxonomy_and_signal'",
      "WHEN 'Spider' THEN 'Araneae'",
      "WHEN 'Domesticated animal' THEN 'Animalia'",
      "WHEN 'Urban wild animal' THEN 'Animalia'",
      "WHEN 'Bee or wasp' THEN 'bee|wasp'",
      "WHEN 'Spider near flowers' THEN 'Spider'",
      "WHEN 'Bird near flowers' THEN 'Bird'",
      "WHEN 'Pollinator habitat' THEN 'Meadow plant'",
      "WHEN 'Wild plant' THEN 'wild'",
      "WHEN 'Pollinator habitat' THEN 'meadow'",
      "JOIN tightened_field_trip_items AS tightened",
      "DELETE FROM public.user_field_trip_item_completions",
      "DELETE FROM public.field_trip_challenge_item_completions",
      "DELETE FROM public.field_trip_scan_progress_receipts",
      "completed_at = NULL",
      "badge_awarded_at = NULL",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Backyard Safari and Park Pollinators use identity-preserving 2/4/4 progressions", async () => {
  const sql = normalized(
    await migrationSql(
      "20260802053044_simplify_backyard_and_pollinator_levels.sql",
    ),
  );

  for (
    const fragment of [
      "('backyard_safari', 'Bird', 1, 10)",
      "('backyard_safari', 'Domesticated animal', 1, 20)",
      "('backyard_safari', 'Butterfly', 2, 10)",
      "('backyard_safari', 'Flowering plant', 2, 40)",
      "('backyard_safari', 'Fungus', 3, 10)",
      "('backyard_safari', 'Moss or lichen', 3, 40)",
      "('park_pollinators', 'Flowering plant', 1, 10)",
      "('park_pollinators', 'Butterfly or moth', 1, 20)",
      "('park_pollinators', 'Bee or wasp', 2, 10)",
      "('park_pollinators', 'Spider', 2, 40)",
      "('park_pollinators', 'Seed or fruiting plant', 3, 10)",
      "('park_pollinators', 'Meadow plant', 3, 40)",
      "SET prompt = 'Dog'",
      "match_type = 'scientific_name'",
      "scientific_name = 'Canis lupus familiaris'",
      "CREATE TEMP TABLE invalid_dog_standard_completions",
      "CREATE TEMP TABLE invalid_dog_challenge_completions",
      "DELETE FROM public.user_field_trip_item_completions",
      "DELETE FROM public.field_trip_challenge_item_completions",
      "BOOL_AND(progress.completed_count >= progress.target_count)",
      "UPDATE public.field_trip_publications",
      "DELETE FROM public.field_trip_challenge_badges",
      "UPDATE public.field_trip_challenge_entries",
      "DELETE FROM public.field_trip_scan_progress_receipts",
      "ON CONFLICT(user_id, challenge_id) DO NOTHING",
      "failed to preserve checklist identities",
      "retained non-Dog completion credit",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("DELETE FROM public.field_trip_scan_goal_preferences"),
    "Pending Capture goal preferences must survive the progression repair",
  );
  assert(
    !sql.includes("DELETE FROM public.field_trip_checklist_items") &&
      !sql.includes("INSERT INTO public.field_trip_checklist_items"),
    "The progression repair must move existing checklist rows in place",
  );
});

Deno.test("Backyard Safari Level 1 auto-enrolls existing and future users without resuming prior state", async () => {
  const sql = normalized(
    await migrationSql(
      "20260803015025_auto_enroll_backyard_safari_level_one.sql",
    ),
  );

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '5min'",
      "JOIN public.field_trip_checklist_items AS item",
      "CREATE OR REPLACE FUNCTION internal.auto_enroll_backyard_safari_level_one()",
      "SECURITY DEFINER SET search_path = ''",
      "ON CONFLICT (user_id, template_id) DO NOTHING",
      "INSERT INTO public.user_field_trip_active_periods",
      "REVOKE ALL ON FUNCTION internal.auto_enroll_backyard_safari_level_one() FROM PUBLIC, anon, authenticated, service_role",
      "CREATE TRIGGER auto_enroll_backyard_safari_level_one_on_user_insert AFTER INSERT ON public.users",
      "WITH backyard_template AS",
      "FROM public.users AS users CROSS JOIN backyard_template",
      "RETURNING id, started_at",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("ON CONFLICT (user_id, template_id) DO UPDATE") &&
      !sql.includes("UPDATE public.user_field_trips"),
    "Auto-enrollment must not resume a stopped, reset, or completed outing",
  );
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

Deno.test("Legacy Backyard Safari rename remains represented in migration history", async () => {
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

Deno.test("Backyard Safari copy is canonical and custom publication titles are preserved", async () => {
  const sql = normalized(
    await migrationSql("20260720014446_update_backyard_safari_copy.sql"),
  );

  for (
    const fragment of [
      "UPDATE public.field_trip_templates",
      "SET title = 'Backyard Safari'",
      "subtitle = 'Observe local species often found in your own backyard.'",
      "WHERE slug = 'backyard_safari'",
      "UPDATE public.field_trip_publications AS publication",
      "SET title = 'Backyard Safari'",
      "AND publication.title = 'Backyard safari'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("DELETE FROM") &&
      !sql.includes("publication.title LIKE") &&
      !sql.includes("publication.title ILIKE"),
    "Copy normalization must preserve progress and user-authored publication titles",
  );
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

Deno.test("Private field trip detail exposes active publication status", async () => {
  const sql = normalized(
    await migrationSql(
      "20260718051748_expose_field_trip_publication_status.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_field_trip_template_detail",
      "'publication_id', ftp.id",
      "'published_at', ftp.published_at",
      "LEFT JOIN public.field_trip_publications ftp ON ftp.user_field_trip_id = uft.id AND ftp.user_id = self_id AND ftp.deleted_at IS NULL",
      "REVOKE ALL ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_template_detail(UUID, UUID, TEXT) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("CREATE OR REPLACE FUNCTION public.get_field_trip_catalog"),
    "publication status must remain scoped to the private detail payload",
  );
  assert(
    !sql.includes("get_field_trip_profile_summaries") &&
      !sql.includes("get_field_trip_capture_context"),
    "publication status must not expand public profile or capture projections",
  );
});

Deno.test("Field trip progress responses preserve the level credited by a scan", async () => {
  const sql = normalized(
    await migrationSql(
      "20260718162409_scope_credited_progress_to_current_attempt.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress",
      "CREATE TEMP TABLE field_trip_new_completions",
      "CREATE TEMP TABLE field_trip_challenge_new_completions",
      "INSERT INTO pg_temp.field_trip_new_completions",
      "INSERT INTO pg_temp.field_trip_challenge_new_completions",
      "'credited_level_number', cp.level_number",
      "'credited_level_title', cp.level_title",
      "'credited_completed_count', cp.completed_count",
      "'credited_target_count', cp.target_count",
      "COUNT(DISTINCT all_items.id)::INTEGER AS target_count",
      "COUNT(DISTINCT all_completions.item_id)::INTEGER AS completed_count",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    (sql.match(/'credited_level_number', cp\.level_number/g) ?? []).length ===
      2,
    "standard and challenge updates must both expose credited-level progress",
  );
  assert(
    (sql.match(/JOIN pg_temp\.field_trip_new_completions/g) ?? []).length ===
        3 &&
      (sql.match(/JOIN pg_temp\.field_trip_challenge_new_completions/g) ?? [])
          .length === 3,
    "responses must stay scoped to completion rows inserted by this application attempt",
  );
});

Deno.test("Field trip lifecycle controls preserve progress and gate scans by active periods", async () => {
  const sql = normalized(
    await migrationSql(
      "20260719160750_field_trip_lifecycle_controls.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.user_field_trip_active_periods",
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_user_field_trip_active_periods_open",
      "ALTER TABLE public.user_field_trip_active_periods ENABLE ROW LEVEL SECURITY",
      "THEN LEAST(uft.hidden_at, uft.completed_at)",
      "GRANT ALL ON TABLE public.user_field_trip_active_periods TO service_role",
      "CREATE OR REPLACE FUNCTION public.stop_field_trip",
      "CREATE OR REPLACE FUNCTION public.reset_field_trip",
      "CREATE OR REPLACE FUNCTION public.get_stopped_field_trip_progress",
      "CREATE OR REPLACE FUNCTION public.start_field_trip",
      "CREATE OR REPLACE FUNCTION public.join_field_trip_challenge",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress",
      "scan_row.timestamp >= period.started_at",
      "scan_row.timestamp <= period.stopped_at",
      "'stopped_progress', row.stopped_progress",
      "DELETE FROM public.user_field_trip_item_completions completion",
      "DELETE FROM public.user_field_trip_active_periods period",
      "IF trip_row.hidden_at IS NOT NULL",
      "GRANT EXECUTE ON FUNCTION public.stop_field_trip(UUID, UUID) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.reset_field_trip(UUID, UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("DELETE FROM public.user_field_trips") &&
      !sql.includes("DELETE FROM public.field_trip_challenge_participants"),
    "Reset must preserve the shared outing row and Seasonal Challenge participation",
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.stop_field_trip(UUID, UUID) TO authenticated",
    ) &&
      !sql.includes(
        "GRANT EXECUTE ON FUNCTION public.reset_field_trip(UUID, UUID) TO authenticated",
      ),
    "Lifecycle RPCs must remain service-role only behind the authenticated Edge action",
  );
});

Deno.test("Field trip lifecycle Edge actions are caller-scoped", async () => {
  const index = normalized(
    await Deno.readTextFile(new URL("index.ts", fieldTripsFunctionDir)),
  );
  const actions = normalized(
    await Deno.readTextFile(new URL("actions.ts", fieldTripsFunctionDir)),
  );
  const db = normalized(
    await Deno.readTextFile(new URL("db.ts", fieldTripsFunctionDir)),
  );

  for (
    const fragment of [
      '"stop"',
      '"reset"',
      'case "stop":',
      'case "reset":',
      'body.user_field_trip_id, "user_field_trip_id"',
      'supabaseAdmin.rpc( "stop_field_trip", { self_id: userId, target_user_field_trip_id: userFieldTripId',
      'supabaseAdmin.rpc( "reset_field_trip", { self_id: userId, target_user_field_trip_id: userFieldTripId',
      'supabaseAdmin.rpc( "get_stopped_field_trip_progress"',
    ]
  ) {
    assertStringIncludes(`${actions} ${index} ${db}`, fragment);
  }

  assert(
    !index.includes("body.self_id") && !index.includes("body.user_id"),
    "Lifecycle actions must derive ownership from the verified caller",
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

Deno.test("Capture context entitlement dependency remains invoker-safe and service-only", async () => {
  const sql = normalized(
    await migrationSql(
      "20260808215410_restore_field_trip_capture_entitlement_helper_access.sql",
    ),
  );

  for (
    const fragment of [
      "public.get_field_trip_capture_context(uuid)",
      "internal.user_has_effective_pro(uuid)",
      "field_trip_capture_entitlement_dependency_missing",
      "field_trip_capture_entitlement_dependency_drift",
      "field_trip_capture_entitlement_helper_acl_unsafe",
      "REVOKE ALL ON FUNCTION internal.user_has_effective_pro(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION internal.user_has_effective_pro(UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.get_field_trip_capture_context",
    ),
    "The ACL repair must not convert or redefine the invoker capture projection",
  );
  assertEquals(
    (sql.match(
      /GRANT EXECUTE ON FUNCTION internal[.]user_has_effective_pro[(]UUID[)] TO service_role/g,
    ) ?? []).length,
    1,
  );
});

Deno.test("Capture context invoker has an explicit source-read allowlist", async () => {
  const sql = normalized(
    await migrationSql(
      "20260808230028_restore_field_trip_capture_context_source_reads.sql",
    ),
  );

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "public.get_field_trip_capture_context(uuid)",
      "internal.user_has_effective_pro(",
      "field_trip_capture_context_source_function_missing",
      "field_trip_capture_context_source_shape_drift",
      "field_trip_capture_context_source_relation_drift",
      "field_trip_capture_context_source_acl_unsafe",
      "GRANT SELECT ON TABLE public.users, public.user_field_trips, public.field_trip_templates, public.field_trip_levels, public.user_field_trip_item_completions, public.field_trip_checklist_items TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.get_field_trip_capture_context",
    ) && !sql.includes("SECURITY DEFINER"),
    "The source-read repair must preserve the invoker projection",
  );
  assertEquals(
    sql.match(/GRANT [^;]+ TO service_role/g) ?? [],
    [
      "GRANT SELECT ON TABLE public.users, public.user_field_trips, public.field_trip_templates, public.field_trip_levels, public.user_field_trip_item_completions, public.field_trip_checklist_items TO service_role",
    ],
    "The source-read repair must contain only the reviewed relation grant",
  );
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
  const actions = normalized(
    await Deno.readTextFile(new URL("actions.ts", fieldTripsFunctionDir)),
  );
  const db = normalized(
    await Deno.readTextFile(new URL("db.ts", fieldTripsFunctionDir)),
  );

  assertStringIncludes(actions, '"capture_context"');
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

Deno.test("First Field trip achievement is indexed, private, and publicly projected without evidence", async () => {
  const rawSql = await migrationSql(
    "20260719045306_first_field_trip_achievement.sql",
  );
  const sql = normalized(rawSql);
  const publicProjection = normalized(
    rawSql.split("-- Explore author profiles expose only")[1] ?? "",
  );

  for (
    const fragment of [
      "CREATE INDEX IF NOT EXISTS idx_user_field_trips_user_completed_at ON public.user_field_trips(user_id, completed_at) WHERE completed_at IS NOT NULL",
      "CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_participants_user_completed_at ON public.field_trip_challenge_participants(user_id, completed_at) WHERE completed_at IS NOT NULL",
      "CREATE OR REPLACE FUNCTION public.get_first_field_trip_achievement_progress( target_user_id UUID )",
      "SECURITY INVOKER",
      "SET search_path = ''",
      "ORDER BY candidate.completed_at ASC, candidate.destination_priority ASC, candidate.source_id ASC",
      "REVOKE ALL ON FUNCTION public.get_first_field_trip_achievement_progress(UUID) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_first_field_trip_achievement_progress(UUID) TO service_role",
      "''type'', ''first_field_trip''",
      "''current_count''",
      "''last_interaction_at''",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !publicProjection.includes("'scan_id'") &&
      !publicProjection.includes("'template_slug'") &&
      !publicProjection.includes("'challenge_id'"),
    "Public award projection must not expose trip evidence or scan ids",
  );
});

Deno.test("First Field trip Edge actions use only the verified user", async () => {
  const index = normalized(
    await Deno.readTextFile(new URL("index.ts", fieldTripsFunctionDir)),
  );
  const actions = normalized(
    await Deno.readTextFile(new URL("actions.ts", fieldTripsFunctionDir)),
  );

  assertStringIncludes(actions, '"achievement_progress"');
  assertStringIncludes(
    index,
    'case "achievement_progress": { const data = await fetchFirstFieldTripAchievementProgress( user.id, supabaseAdmin',
  );
  assertStringIncludes(
    index,
    "first_field_trip_achievement: progress.firstFieldTripAchievement",
  );
  assertStringIncludes(
    index,
    "first_field_trip_achievement_newly_unlocked: progress.firstFieldTripAchievementNewlyUnlocked",
  );
  assert(
    !index.includes("body.target_user_id") && !index.includes("body.user_id"),
    "Achievement progress must not accept an account id from the request body",
  );
});

Deno.test("Persistent scan contributions enforce one ranked credit per active experience", async () => {
  const sql = normalized(
    await migrationSql(
      "20260722025411_persistent_field_trip_scan_contributions.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE TABLE public.field_trip_scan_goal_preferences",
      "CREATE UNIQUE INDEX user_field_trip_item_completions_one_credit_per_scan ON public.user_field_trip_item_completions(user_field_trip_id, scan_id)",
      "CREATE UNIQUE INDEX field_trip_challenge_item_completions_one_credit_per_scan ON public.field_trip_challenge_item_completions(participation_id, scan_id)",
      "CREATE INDEX user_field_trip_item_completions_scan_lookup ON public.user_field_trip_item_completions(scan_id, user_field_trip_id)",
      "CREATE INDEX field_trip_challenge_item_completions_scan_lookup ON public.field_trip_challenge_item_completions(scan_id, participation_id)",
      "CREATE OR REPLACE FUNCTION public.apply_field_trip_scan_progress_v2",
      "stored_preferred_user_field_trip_id = trip_row.id AND stored_preferred_item_id = item.id",
      "public.field_trip_checklist_match_rank",
      "item.sort_order, item.id",
      "FROM public.user_field_trip_active_periods period",
      "scan_row.timestamp >= period.started_at",
      "scan_row.timestamp <= period.stopped_at",
      "scan_row.timestamp >= participation.joined_at",
      "scan_row.timestamp BETWEEN challenge.starts_at AND challenge.ends_at",
      "public.user_field_trip_item_completions existing_completion",
      "public.field_trip_challenge_item_completions existing_completion",
      "participation.hidden_at IS NULL AND challenge.is_active = TRUE",
      "removed_item_ids",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("INSERT INTO public.user_field_trips(user_id, template_id"),
    "Scan matching must not auto-start a standard outing",
  );
  assert(
    !sql.includes("NOW() BETWEEN challenge.starts_at AND challenge.ends_at"),
    "Offline Event scans must be evaluated by capture time, not upload time",
  );
});

Deno.test("Persistent contribution lookup stays private and evidence-minimal", async () => {
  const sql = normalized(
    await migrationSql(
      "20260722025411_persistent_field_trip_scan_contributions.sql",
    ),
  );

  for (
    const fragment of [
      "ALTER TABLE public.field_trip_scan_goal_preferences ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE public.field_trip_scan_goal_preferences FROM PUBLIC, anon, authenticated",
      "CREATE OR REPLACE FUNCTION public.get_field_trip_scan_contributions",
      "scan.user_id = self_id",
      "REVOKE ALL ON FUNCTION public.get_field_trip_scan_contributions(UUID, UUID) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_field_trip_scan_contributions(UUID, UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const lookup = sql.split(
    "CREATE OR REPLACE FUNCTION public.get_field_trip_scan_contributions",
  )[1] ?? "";
  for (
    const forbidden of [
      "image_storage_urls",
      "gps_latitude",
      "gps_longitude",
      "field_notes",
      "location_name",
      "public_notes",
    ]
  ) {
    assert(
      !lookup.includes(forbidden),
      `Scan contribution rows must not expose private evidence: ${forbidden}`,
    );
  }
});
