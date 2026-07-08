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
