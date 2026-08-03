import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type TemplateFixture = {
  template_id: string;
  slug: string;
  level_id: string;
  is_active: boolean;
};

type CaptureOuting = {
  user_field_trip_id: string;
  template_id: string;
  template_slug: string;
  outing_title: string;
  last_engaged_at: string;
  level_number: number;
  level_title: string;
  completed_count: number;
  target_count: number;
  targets: Array<{
    item_id: string;
    prompt: string;
    sort_order: number;
    has_guide: boolean;
  }>;
};

Deno.test("Field trip capture context preserves standard field trips and excludes evidence", async () => {
  await withExploreDbTest(
    "fieldTripCaptureContextDb.test",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const emptyViewerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      await insertUser(client, viewerId, "Capture Viewer");
      await insertUser(client, emptyViewerId, "Empty Viewer");
      await insertSpecies(client, speciesId, "Rosa captura");

      const fixtures = await client.queryObject<TemplateFixture>(
        `
        SELECT
          template.id AS template_id,
          template.slug,
          level.id AS level_id,
          template.is_active
        FROM public.field_trip_templates template
        JOIN public.field_trip_levels level
          ON level.template_id = template.id
         AND level.level_number = 1
        WHERE template.slug IN ('backyard_safari', 'park_pollinators', 'forest_edges')
        ORDER BY template.slug
        `,
      );
      assertEquals(fixtures.rows.length, 3);
      const bySlug = new Map(fixtures.rows.map((row) => [row.slug, row]));
      const backyard = bySlug.get("backyard_safari");
      const park = bySlug.get("park_pollinators");
      const forest = bySlug.get("forest_edges");
      assert(backyard && park && forest);
      assertEquals(forest.is_active, false);

      const enrolledBackyard = await client.queryObject<{
        trip_id: string;
        current_level_number: number;
        is_profile_visible: boolean;
        hidden_at: string | null;
        period_count: number;
        period_matches_start: boolean;
      }>(
        `
        SELECT
          trip.id::TEXT AS trip_id,
          trip.current_level_number,
          trip.is_profile_visible,
          trip.hidden_at::TEXT AS hidden_at,
          COUNT(period.id)::INTEGER AS period_count,
          BOOL_AND(period.started_at = trip.started_at) AS period_matches_start
        FROM public.user_field_trips AS trip
        JOIN public.user_field_trip_active_periods AS period
          ON period.user_field_trip_id = trip.id
        WHERE trip.user_id = $1
          AND trip.template_id = $2
        GROUP BY trip.id
        `,
        [viewerId, backyard.template_id],
      );
      assertEquals(enrolledBackyard.rows.length, 1);
      assertEquals(enrolledBackyard.rows[0].current_level_number, 1);
      assertEquals(enrolledBackyard.rows[0].is_profile_visible, true);
      assertEquals(enrolledBackyard.rows[0].hidden_at, null);
      assertEquals(enrolledBackyard.rows[0].period_count, 1);
      assertEquals(enrolledBackyard.rows[0].period_matches_start, true);

      await client.queryArray(
        `
        UPDATE public.field_trip_templates
        SET is_active = TRUE,
            is_pro_only = FALSE,
            is_rotating_free = FALSE
        WHERE id IN ($1, $2)
        `,
        [backyard.template_id, park.template_id],
      );

      const inaccessibleTemplateId = crypto.randomUUID();
      const inaccessibleLevelId = crypto.randomUUID();
      const inaccessibleItemId = crypto.randomUUID();
      const inaccessibleSlug = `capture_pro_${
        inaccessibleTemplateId.slice(0, 8)
      }`;
      await client.queryArray(
        `
        INSERT INTO public.field_trip_templates (
          id, slug, title, difficulty, is_pro_only, is_rotating_free,
          is_active, sort_order
        )
        VALUES ($1, $2, 'Capture Pro fixture', 'starter', TRUE, FALSE, TRUE, 999)
        `,
        [inaccessibleTemplateId, inaccessibleSlug],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_levels (
          id, template_id, level_number, title
        )
        VALUES ($1, $2, 1, 'Fixture level')
        `,
        [inaccessibleLevelId, inaccessibleTemplateId],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_checklist_items (
          id, level_id, prompt, match_type, semantic_tag, sort_order
        )
        VALUES ($1, $2, 'Fixture target', 'semantic_tag', 'fixture', 10)
        `,
        [inaccessibleItemId, inaccessibleLevelId],
      );

      const backyardTripId = enrolledBackyard.rows[0].trip_id;
      const parkTripId = crypto.randomUUID();
      const inactiveTripId = crypto.randomUUID();
      const inaccessibleTripId = crypto.randomUUID();
      await client.queryArray(
        `
        UPDATE public.user_field_trips
        SET started_at = '2026-07-17T10:00:00Z'
        WHERE id = $1
        `,
        [backyardTripId],
      );
      await client.queryArray(
        `
        UPDATE public.user_field_trip_active_periods
        SET started_at = '2026-07-17T10:00:00Z'
        WHERE user_field_trip_id = $1
        `,
        [backyardTripId],
      );
      await client.queryArray(
        `
        INSERT INTO public.user_field_trips (
          id, user_id, template_id, started_at, current_level_number
        )
        VALUES
          ($1, $2, $3, '2026-07-17T11:00:00Z', 1),
          ($4, $2, $5, '2026-07-17T12:00:00Z', 1),
          ($6, $2, $7, '2026-07-17T13:00:00Z', 1)
        `,
        [
          parkTripId,
          viewerId,
          park.template_id,
          inactiveTripId,
          forest.template_id,
          inaccessibleTripId,
          inaccessibleTemplateId,
        ],
      );

      const seasonalChallengeId = crypto.randomUUID();
      const seasonalParticipationId = crypto.randomUUID();
      const seasonalSlug = `capture_seasonal_${
        seasonalChallengeId.slice(0, 8)
      }`;
      await client.queryArray(
        `INSERT INTO public.field_trip_challenges (
          id, template_id, slug, title, starts_at, ends_at
        )
        VALUES (
          $1, $2, $3 || '_challenge', 'Seasonal capture challenge',
          '2026-07-01T00:00:00Z', '2026-07-31T23:59:59Z'
        )`,
        [seasonalChallengeId, backyard.template_id, seasonalSlug],
      );
      await client.queryArray(
        `INSERT INTO public.field_trip_challenge_participants (
          id, challenge_id, user_id, user_field_trip_id
        )
        VALUES ($1, $2, $3, $4)`,
        [
          seasonalParticipationId,
          seasonalChallengeId,
          viewerId,
          backyardTripId,
        ],
      );

      const currentItems = await client.queryObject<{
        item_id: string;
        sort_order: number;
      }>(
        `
        SELECT id AS item_id, sort_order
        FROM public.field_trip_checklist_items
        WHERE level_id = $1
        ORDER BY sort_order, id
        `,
        [backyard.level_id],
      );
      assert(currentItems.rows.length > 1);

      await insertScan(client, {
        id: scanId,
        userId: viewerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      await client.queryArray(
        `
        INSERT INTO public.user_field_trip_item_completions (
          user_field_trip_id, item_id, scan_id, species_id,
          common_name, scientific_name, completed_at
        )
        VALUES ($1, $2, $3, $4, 'Private Rose', 'Rosa captura', '2026-07-17T13:00:00Z')
        `,
        [backyardTripId, currentItems.rows[0].item_id, scanId, speciesId],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_challenge_item_completions (
          participation_id, item_id, scan_id, species_id,
          common_name, scientific_name, completed_at
        )
        VALUES ($1, $2, $3, $4, 'Challenge-only Rose', 'Rosa captura', '2026-07-17T13:30:00Z')
        `,
        [
          seasonalParticipationId,
          currentItems.rows[1].item_id,
          scanId,
          speciesId,
        ],
      );

      const result = await client.queryObject<{ data: CaptureOuting[] }>(
        `SELECT public.get_field_trip_capture_context($1)::jsonb AS data`,
        [viewerId],
      );
      const outings = result.rows[0].data;

      assertEquals(outings.map((outing) => outing.template_slug), [
        "backyard_safari",
        "park_pollinators",
      ]);
      assertEquals(outings[0].completed_count, 1);
      assertEquals(outings[0].target_count, currentItems.rows.length);
      assertEquals(
        outings[0].targets.map((target) => target.item_id),
        currentItems.rows.slice(1).map((item) => item.item_id),
      );
      assertEquals(
        outings[0].targets.map((target) => target.sort_order),
        currentItems.rows.slice(1).map((item) => item.sort_order),
      );
      assert(!JSON.stringify(outings).includes(scanId));
      assert(!JSON.stringify(outings).includes("Private Rose"));
      assert(!JSON.stringify(outings).includes("Challenge-only Rose"));
      assert(!JSON.stringify(outings).includes("Rosa captura"));

      const emptyResult = await client.queryObject<{ data: CaptureOuting[] }>(
        `SELECT public.get_field_trip_capture_context($1)::jsonb AS data`,
        [emptyViewerId],
      );
      assertEquals(emptyResult.rows[0].data.length, 1);
      assertEquals(
        emptyResult.rows[0].data[0].template_slug,
        "backyard_safari",
      );
      assertEquals(emptyResult.rows[0].data[0].level_number, 1);
      assertEquals(emptyResult.rows[0].data[0].completed_count, 0);
      assertEquals(
        emptyResult.rows[0].data[0].target_count,
        currentItems.rows.length,
      );

      const privileges = await client.queryObject<{
        anonymous: boolean;
        authenticated: boolean;
        service_role: boolean;
      }>(
        `
        SELECT
          has_function_privilege('anon', 'public.get_field_trip_capture_context(uuid)', 'EXECUTE') AS anonymous,
          has_function_privilege('authenticated', 'public.get_field_trip_capture_context(uuid)', 'EXECUTE') AS authenticated,
          has_function_privilege('service_role', 'public.get_field_trip_capture_context(uuid)', 'EXECUTE') AS service_role
        `,
      );
      assertEquals(privileges.rows[0], {
        anonymous: false,
        authenticated: false,
        service_role: true,
      });

      const enrollmentPrivileges = await client.queryObject<{
        anonymous: boolean;
        authenticated: boolean;
        service_role: boolean;
      }>(
        `
        SELECT
          has_function_privilege('anon', 'internal.auto_enroll_backyard_safari_level_one()', 'EXECUTE') AS anonymous,
          has_function_privilege('authenticated', 'internal.auto_enroll_backyard_safari_level_one()', 'EXECUTE') AS authenticated,
          has_function_privilege('service_role', 'internal.auto_enroll_backyard_safari_level_one()', 'EXECUTE') AS service_role
        `,
      );
      assertEquals(enrollmentPrivileges.rows[0], {
        anonymous: false,
        authenticated: false,
        service_role: false,
      });
    },
  );
});
