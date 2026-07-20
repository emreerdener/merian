import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type LifecycleFixture = {
  templateId: string;
  tripId: string;
  itemIds: string[];
};

Deno.test("stopped outings save progress and exclude scans captured during stopped gaps", async () => {
  await withExploreDbTest(
    "fieldTripLifecycleDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const speciesIds = [
        crypto.randomUUID(),
        crypto.randomUUID(),
        crypto.randomUUID(),
      ];
      const scanIds = [
        crypto.randomUUID(),
        crypto.randomUUID(),
        crypto.randomUUID(),
      ];

      await insertUser(client, userId, "Lifecycle Viewer");
      for (const [index, speciesId] of speciesIds.entries()) {
        await insertSpecies(
          client,
          speciesId,
          `Testus lifecycle ${index} ${speciesId.slice(0, 8)}`,
        );
        await insertScan(client, {
          id: scanIds[index],
          userId,
          speciesId,
          confirmedSpeciesId: speciesId,
          latitude: 30.2672,
          longitude: -97.7431,
          geoprivacy: "private",
        });
      }

      const fixture = await insertLifecycleFixture(
        client,
        userId,
        speciesIds,
      );

      await client.queryArray(
        `UPDATE public.scans SET timestamp = NOW() - INTERVAL '2 hours' WHERE id = $1`,
        [scanIds[0]],
      );
      await client.queryArray(
        `SELECT public.stop_field_trip($1, $2)`,
        [userId, fixture.tripId],
      );

      // Give this transaction deterministic period boundaries. NOW() is stable
      // across the transaction while production mutations use separate requests.
      await client.queryArray(
        `
          UPDATE public.user_field_trip_active_periods
          SET stopped_at = NOW() - INTERVAL '1 hour'
          WHERE user_field_trip_id = $1
        `,
        [fixture.tripId],
      );
      await client.queryArray(
        `
          UPDATE public.user_field_trips
          SET hidden_at = NOW() - INTERVAL '1 hour'
          WHERE id = $1
        `,
        [fixture.tripId],
      );

      assertEquals(
        await templateIsInCaptureContext(client, userId, fixture.templateId),
        false,
      );
      assertEquals(
        await templateIsInActiveProfile(client, userId, fixture.templateId),
        false,
      );

      const lateApproval = await applyProgress(client, userId, scanIds[0]);
      assert(
        lateApproval.some((row) => row.template_id === fixture.templateId),
      );

      const stopped = await stoppedProgress(client, userId, fixture.templateId);
      assertEquals(stopped.length, 1);
      assertEquals(stopped[0].stopped_progress.completed_count, 1);

      await client.queryArray(
        `UPDATE public.scans SET timestamp = NOW() - INTERVAL '30 minutes' WHERE id = $1`,
        [scanIds[1]],
      );
      await client.queryArray(
        `SELECT public.start_field_trip($1, $2)`,
        [userId, fixture.templateId],
      );

      const gapApproval = await applyProgress(client, userId, scanIds[1]);
      assertEquals(
        gapApproval.filter((row) => row.template_id === fixture.templateId),
        [],
      );

      await client.queryArray(
        `UPDATE public.scans SET timestamp = NOW() + INTERVAL '1 minute' WHERE id = $1`,
        [scanIds[2]],
      );
      const resumedApproval = await applyProgress(client, userId, scanIds[2]);
      assert(
        resumedApproval.some((row) => row.template_id === fixture.templateId),
      );

      await client.queryArray(
        `SELECT public.stop_field_trip($1, $2)`,
        [userId, fixture.tripId],
      );
      await client.queryArray(
        `SELECT public.stop_field_trip($1, $2)`,
        [userId, fixture.tripId],
      );

      const periods = await client.queryObject<{ count: number }>(
        `
          SELECT COUNT(*)::INTEGER AS count
          FROM public.user_field_trip_active_periods
          WHERE user_field_trip_id = $1
        `,
        [fixture.tripId],
      );
      assertEquals(periods.rows[0].count, 2);

      const idempotent = await applyProgress(client, userId, scanIds[2]);
      assertEquals(
        idempotent.filter((row) => row.template_id === fixture.templateId),
        [],
      );
    },
  );
});

Deno.test("reset preserves challenges, blocks historical scans, and allows a new automatic start", async () => {
  await withExploreDbTest(
    "fieldTripLifecycleDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const speciesIds = [crypto.randomUUID(), crypto.randomUUID()];
      const scanIds = [crypto.randomUUID(), crypto.randomUUID()];
      await insertUser(client, userId, "Reset Viewer");

      for (const [index, speciesId] of speciesIds.entries()) {
        await insertSpecies(
          client,
          speciesId,
          `Testus reset ${index} ${speciesId.slice(0, 8)}`,
        );
        await insertScan(client, {
          id: scanIds[index],
          userId,
          speciesId,
          confirmedSpeciesId: speciesId,
          latitude: 30.2672,
          longitude: -97.7431,
          geoprivacy: "private",
        });
      }

      const fixture = await insertLifecycleFixture(
        client,
        userId,
        speciesIds,
      );
      await client.queryArray(
        `
          INSERT INTO public.user_field_trip_item_completions(
            user_field_trip_id, item_id, scan_id, species_id, scientific_name
          )
          VALUES ($1, $2, $3, $4, 'Testus reset fixture')
        `,
        [fixture.tripId, fixture.itemIds[0], scanIds[0], speciesIds[0]],
      );

      const challengeId = crypto.randomUUID();
      const participationId = crypto.randomUUID();
      await client.queryArray(
        `
          INSERT INTO public.field_trip_challenges(
            id, template_id, slug, title, starts_at, ends_at, is_active
          )
          VALUES (
            $1, $2, $3, 'Reset preservation challenge',
            NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day', TRUE
          )
        `,
        [challengeId, fixture.templateId, `reset_${challengeId.slice(0, 8)}`],
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_challenge_participants(
            id, challenge_id, user_id, user_field_trip_id
          )
          VALUES ($1, $2, $3, $4)
        `,
        [participationId, challengeId, userId, fixture.tripId],
      );

      await client.queryArray(
        `SELECT public.reset_field_trip($1, $2)`,
        [userId, fixture.tripId],
      );

      const resetState = await client.queryObject<{
        trip_count: number;
        completion_count: number;
        period_count: number;
        participation_count: number;
        hidden_at: string | null;
        started_at: string;
      }>(
        `
          SELECT
            (SELECT COUNT(*)::INTEGER FROM public.user_field_trips WHERE id = $1) AS trip_count,
            (SELECT COUNT(*)::INTEGER FROM public.user_field_trip_item_completions WHERE user_field_trip_id = $1) AS completion_count,
            (SELECT COUNT(*)::INTEGER FROM public.user_field_trip_active_periods WHERE user_field_trip_id = $1) AS period_count,
            (SELECT COUNT(*)::INTEGER FROM public.field_trip_challenge_participants WHERE id = $2) AS participation_count,
            (SELECT hidden_at::TEXT FROM public.user_field_trips WHERE id = $1) AS hidden_at,
            (SELECT started_at::TEXT FROM public.user_field_trips WHERE id = $1) AS started_at
        `,
        [fixture.tripId, participationId],
      );
      assertEquals(resetState.rows[0].trip_count, 1);
      assertEquals(resetState.rows[0].completion_count, 0);
      assertEquals(resetState.rows[0].period_count, 0);
      assertEquals(resetState.rows[0].participation_count, 1);
      assert(resetState.rows[0].hidden_at !== null);
      assertEquals(
        (await stoppedProgress(client, userId, fixture.templateId)).length,
        0,
      );

      await client.queryArray(
        `SELECT public.reset_field_trip($1, $2)`,
        [userId, fixture.tripId],
      );
      const idempotentReset = await client.queryObject<{
        started_at: string;
        period_count: number;
      }>(
        `
          SELECT
            started_at::TEXT AS started_at,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.user_field_trip_active_periods
              WHERE user_field_trip_id = $1
            ) AS period_count
          FROM public.user_field_trips
          WHERE id = $1
        `,
        [fixture.tripId],
      );
      assertEquals(
        idempotentReset.rows[0].started_at,
        resetState.rows[0].started_at,
      );
      assertEquals(idempotentReset.rows[0].period_count, 0);

      await client.queryArray(
        `
          UPDATE public.scans
          SET timestamp = (
            SELECT started_at - INTERVAL '1 hour'
            FROM public.user_field_trips
            WHERE id = $1
          )
          WHERE id = $2
        `,
        [fixture.tripId, scanIds[0]],
      );
      const historical = await applyProgress(client, userId, scanIds[0]);
      assertEquals(
        historical.filter((row) => row.template_id === fixture.templateId),
        [],
      );

      await client.queryArray(
        `
          UPDATE public.scans
          SET timestamp = (
            SELECT started_at + INTERVAL '1 minute'
            FROM public.user_field_trips
            WHERE id = $1
          )
          WHERE id = $2
        `,
        [fixture.tripId, scanIds[1]],
      );
      const automaticStart = await applyProgress(client, userId, scanIds[1]);
      assert(
        automaticStart.some((row) => row.template_id === fixture.templateId),
      );

      const restarted = await client.queryObject<{
        hidden_at: string | null;
        period_count: number;
      }>(
        `
          SELECT
            uft.hidden_at::TEXT AS hidden_at,
            COUNT(period.id)::INTEGER AS period_count
          FROM public.user_field_trips uft
          LEFT JOIN public.user_field_trip_active_periods period
            ON period.user_field_trip_id = uft.id
          WHERE uft.id = $1
          GROUP BY uft.id
        `,
        [fixture.tripId],
      );
      assertEquals(restarted.rows[0].hidden_at, null);
      assertEquals(restarted.rows[0].period_count, 1);

      await client.queryArray(
        `UPDATE public.user_field_trips SET completed_at = NOW() WHERE id = $1`,
        [fixture.tripId],
      );
      await assertRejects(
        () =>
          client.queryArray(
            `SELECT public.reset_field_trip($1, $2)`,
            [userId, fixture.tripId],
          ),
        Error,
        "Completed Field Trips cannot be reset",
      );
    },
  );
});

async function insertLifecycleFixture(
  client: Client,
  userId: string,
  speciesIds: string[],
): Promise<LifecycleFixture> {
  const templateId = crypto.randomUUID();
  const tripId = crypto.randomUUID();
  const levelId = crypto.randomUUID();
  const itemIds = speciesIds.map(() => crypto.randomUUID());
  const suffix = templateId.slice(0, 8);

  await client.queryArray(
    `
      INSERT INTO public.field_trip_templates(
        id, slug, title, difficulty, is_pro_only, is_rotating_free,
        is_active, sort_order
      )
      VALUES ($1, $2, 'Lifecycle fixture', 'starter', FALSE, FALSE, TRUE, 999)
    `,
    [templateId, `lifecycle_${suffix}`],
  );
  await client.queryArray(
    `
      INSERT INTO public.field_trip_levels(id, template_id, level_number, title)
      VALUES ($1, $2, 1, 'Lifecycle level')
    `,
    [levelId, templateId],
  );
  for (const [index, speciesId] of speciesIds.entries()) {
    await client.queryArray(
      `
        INSERT INTO public.field_trip_checklist_items(
          id, level_id, prompt, match_type, species_id, sort_order
        )
        VALUES ($1, $2, $3, 'species', $4, $5)
      `,
      [itemIds[index], levelId, `Species ${index + 1}`, speciesId, index],
    );
  }
  await client.queryArray(
    `
      INSERT INTO public.user_field_trips(
        id, user_id, template_id, started_at, current_level_number,
        is_profile_visible
      )
      VALUES ($1, $2, $3, NOW() - INTERVAL '3 hours', 1, TRUE)
    `,
    [tripId, userId, templateId],
  );
  await client.queryArray(
    `
      INSERT INTO public.user_field_trip_active_periods(
        user_field_trip_id, started_at
      )
      VALUES ($1, NOW() - INTERVAL '3 hours')
    `,
    [tripId],
  );

  return { templateId, tripId, itemIds };
}

async function applyProgress(
  client: Client,
  userId: string,
  scanId: string,
): Promise<Array<{ template_id: string }>> {
  const result = await client.queryObject<{
    data: Array<{ template_id: string }>;
  }>(
    `SELECT public.apply_field_trip_scan_progress($1, $2)::jsonb AS data`,
    [userId, scanId],
  );
  return result.rows[0].data;
}

async function stoppedProgress(
  client: Client,
  userId: string,
  templateId: string,
): Promise<
  Array<{
    stopped_progress: { completed_count: number };
  }>
> {
  const result = await client.queryObject<{
    data: Array<{ stopped_progress: { completed_count: number } }>;
  }>(
    `SELECT public.get_stopped_field_trip_progress($1, $2, NULL)::jsonb AS data`,
    [userId, templateId],
  );
  return result.rows[0].data;
}

async function templateIsInCaptureContext(
  client: Client,
  userId: string,
  templateId: string,
): Promise<boolean> {
  const result = await client.queryObject<{ present: boolean }>(
    `
      SELECT EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(public.get_field_trip_capture_context($1)) row
        WHERE row->>'template_id' = $2
      ) AS present
    `,
    [userId, templateId],
  );
  return result.rows[0].present;
}

async function templateIsInActiveProfile(
  client: Client,
  userId: string,
  templateId: string,
): Promise<boolean> {
  const result = await client.queryObject<{ present: boolean }>(
    `
      SELECT EXISTS (
        SELECT 1
        FROM JSONB_ARRAY_ELEMENTS(
          public.get_field_trip_profile_summaries($1, $1, 6)->'active'
        ) row
        WHERE row->>'template_id' = $2
      ) AS present
    `,
    [userId, templateId],
  );
  return result.rows[0].present;
}
