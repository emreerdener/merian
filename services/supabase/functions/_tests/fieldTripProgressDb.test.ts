import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ProgressItem = {
  item_id: string;
};

type StandardProgressUpdate = {
  user_field_trip_id: string;
  template_id: string;
  current_level_number: number;
  credited_level_number: number;
  credited_completed_count: number;
  credited_target_count: number;
  newly_completed_items: ProgressItem[];
  removed_item_ids: string[];
};

type ChallengeProgressUpdate = {
  participation_id: string;
  challenge_id: string;
  current_level_number: number;
  credited_level_number: number;
  credited_completed_count: number;
  credited_target_count: number;
  newly_completed_items: ProgressItem[];
  removed_item_ids: string[];
};

type ScanContribution = {
  source_kind: "standard_outing" | "event";
  source_id: string;
  item_id: string;
};

Deno.test("Field trip progress requires starts and corrections remove original-level credit", async () => {
  await withExploreDbTest(
    "fieldTripProgressDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const firstSpeciesId = crypto.randomUUID();
      const secondSpeciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const templateId = crypto.randomUUID();
      const firstLevelId = crypto.randomUUID();
      const secondLevelId = crypto.randomUUID();
      const firstItemId = crypto.randomUUID();
      const secondItemId = crypto.randomUUID();
      const challengeId = crypto.randomUUID();
      const participationId = crypto.randomUUID();
      const userFieldTripId = crypto.randomUUID();
      const suffix = templateId.slice(0, 8);

      await insertUser(client, userId, "Progress Viewer");
      await insertSpecies(client, firstSpeciesId, `Testus progressa ${suffix}`);
      await insertSpecies(
        client,
        secondSpeciesId,
        `Testus progressa secunda ${suffix}`,
      );
      await insertScan(client, {
        id: scanId,
        userId,
        speciesId: firstSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      await client.queryArray(
        `UPDATE public.scans SET timestamp = NOW() - INTERVAL '30 minutes' WHERE id = $1`,
        [scanId],
      );

      await client.queryArray(
        `
        INSERT INTO public.field_trip_templates (
          id, slug, title, difficulty, is_pro_only, is_rotating_free,
          is_active, sort_order
        )
        VALUES ($1, $2, 'Credited progress fixture', 'starter', FALSE, FALSE, TRUE, 999)
        `,
        [templateId, `credited_progress_${suffix}`],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_levels (id, template_id, level_number, title)
        VALUES
          ($1, $3, 1, 'Fixture level 1'),
          ($2, $3, 2, 'Fixture level 2')
        `,
        [firstLevelId, secondLevelId, templateId],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_checklist_items (
          id, level_id, prompt, match_type, species_id, sort_order
        )
        VALUES
          ($1, $3, 'First exact species', 'species', $5, 10),
          ($2, $4, 'Second exact species', 'species', $6, 10)
        `,
        [
          firstItemId,
          secondItemId,
          firstLevelId,
          secondLevelId,
          firstSpeciesId,
          secondSpeciesId,
        ],
      );

      const beforeExplicitStart = await applyStandardProgress(
        client,
        userId,
        scanId,
      );
      assertEquals(
        beforeExplicitStart.filter((update) =>
          update.template_id === templateId
        ),
        [],
      );
      const autoStarted = await client.queryObject<{ count: bigint }>(
        `
        SELECT COUNT(*)::bigint AS count
        FROM public.user_field_trips
        WHERE user_id = $1 AND template_id = $2
        `,
        [userId, templateId],
      );
      assertEquals(autoStarted.rows[0].count, 0n);

      await client.queryArray(
        `
        INSERT INTO public.user_field_trips (
          id, user_id, template_id, started_at, current_level_number,
          is_profile_visible, hidden_at
        )
        VALUES ($1, $2, $3, NOW() - INTERVAL '1 hour', 1, TRUE, NULL)
        `,
        [userFieldTripId, userId, templateId],
      );
      await client.queryArray(
        `
        INSERT INTO public.user_field_trip_active_periods (
          user_field_trip_id, started_at, stopped_at
        )
        VALUES (
          $1,
          NOW() - INTERVAL '1 hour',
          NOW() - INTERVAL '10 minutes'
        )
        `,
        [userFieldTripId],
      );
      await client.queryArray(
        `UPDATE public.user_field_trips SET hidden_at = NOW() - INTERVAL '10 minutes' WHERE id = $1`,
        [userFieldTripId],
      );

      const firstStandard = await applyStandardProgress(client, userId, scanId);
      const firstStandardFixture = firstStandard.find((update) =>
        update.template_id === templateId
      );
      assert(firstStandardFixture);
      assertEquals(firstStandardFixture.current_level_number, 2);
      assertCreditedUpdate(firstStandardFixture, 1, firstItemId);

      await client.queryArray(
        `
        INSERT INTO public.field_trip_challenges (
          id, template_id, slug, title, starts_at, ends_at,
          suggested_hashtags, is_active
        )
        VALUES (
          $1, $2, $3, 'Credited progress challenge',
          NOW() - INTERVAL '1 hour', NOW() - INTERVAL '10 minutes',
          ARRAY['creditedprogress'], TRUE
        )
        `,
        [challengeId, templateId, `credited_progress_challenge_${suffix}`],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_challenge_participants (
          id, challenge_id, user_id, user_field_trip_id, joined_at,
          current_level_number
        )
        VALUES ($1, $2, $3, $4, NOW() - INTERVAL '1 hour', 1)
        `,
        [
          participationId,
          challengeId,
          userId,
          userFieldTripId,
        ],
      );

      const firstChallenge = await applyChallengeProgress(
        client,
        userId,
        scanId,
      );
      const firstChallengeFixture = firstChallenge.find((update) =>
        update.challenge_id === challengeId
      );
      assert(firstChallengeFixture);
      assertEquals(firstChallengeFixture.current_level_number, 2);
      assertCreditedUpdate(firstChallengeFixture, 1, firstItemId);

      const contributions = await getScanContributions(client, userId, scanId);
      assertEquals(contributions.length, 2);
      const standardContribution = contributions.find((row) =>
        row.source_kind === "standard_outing"
      );
      const eventContribution = contributions.find((row) =>
        row.source_kind === "event"
      );
      assert(standardContribution);
      assert(eventContribution);
      assertEquals(standardContribution.source_id, userFieldTripId);
      assertEquals(standardContribution.item_id, firstItemId);
      assertEquals(eventContribution.source_id, participationId);
      assertEquals(eventContribution.item_id, firstItemId);
      assertEquals(
        await getScanContributions(client, crypto.randomUUID(), scanId),
        [],
      );

      await client.queryArray(
        `UPDATE public.field_trip_templates SET is_active = FALSE WHERE id = $1`,
        [templateId],
      );
      await client.queryArray(
        `UPDATE public.field_trip_challenges SET is_active = FALSE WHERE id = $1`,
        [challengeId],
      );
      await client.queryArray(
        `UPDATE public.field_trip_challenge_participants SET hidden_at = NOW() WHERE id = $1`,
        [participationId],
      );

      await client.queryArray(
        `UPDATE public.scans SET confirmed_species_id = $1 WHERE id = $2`,
        [secondSpeciesId, scanId],
      );

      const secondStandard = await applyStandardProgress(
        client,
        userId,
        scanId,
      );
      const secondStandardFixtures = secondStandard.filter((update) =>
        update.template_id === templateId
      );
      assertEquals(secondStandardFixtures.length, 1);
      assertCorrectionRemoval(secondStandardFixtures[0], 1, firstItemId);

      const secondChallenge = await applyChallengeProgress(
        client,
        userId,
        scanId,
      );
      const secondChallengeFixtures = secondChallenge.filter((update) =>
        update.challenge_id === challengeId
      );
      assertEquals(secondChallengeFixtures.length, 1);
      assertCorrectionRemoval(secondChallengeFixtures[0], 1, firstItemId);

      assertEquals(await getScanContributions(client, userId, scanId), []);

      const idempotentStandard = await applyStandardProgress(
        client,
        userId,
        scanId,
      );
      assertEquals(
        idempotentStandard.filter((update) =>
          update.template_id === templateId
        ),
        [],
      );
      const idempotentChallenge = await applyChallengeProgress(
        client,
        userId,
        scanId,
      );
      assertEquals(
        idempotentChallenge.filter((update) =>
          update.challenge_id === challengeId
        ),
        [],
      );
    },
  );
});

Deno.test("Field trip progress prefers the visible Capture goal before specificity fallback", async () => {
  await withExploreDbTest(
    "fieldTripPreferredGoalDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const templateId = crypto.randomUUID();
      const levelId = crypto.randomUUID();
      const exactItemId = crypto.randomUUID();
      const taxonomyItemId = crypto.randomUUID();
      const userFieldTripId = crypto.randomUUID();
      const suffix = templateId.slice(0, 8);

      await insertUser(client, userId, "Preferred Goal Viewer");
      await insertSpecies(client, speciesId, `Rosa preferata ${suffix}`);
      await insertScan(client, {
        id: scanId,
        userId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      await client.queryArray(
        `
        INSERT INTO public.field_trip_templates (
          id, slug, title, difficulty, is_pro_only, is_rotating_free,
          is_active, sort_order
        )
        VALUES ($1, $2, 'Preferred goal fixture', 'starter', FALSE, FALSE, TRUE, 998)
        `,
        [templateId, `preferred_goal_${suffix}`],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_levels (id, template_id, level_number, title)
        VALUES ($1, $2, 1, 'Fixture level')
        `,
        [levelId, templateId],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_checklist_items (
          id, level_id, prompt, match_type, species_id,
          taxonomy_kingdom, sort_order
        )
        VALUES
          ($1, $3, 'Exact rose', 'species', $4, NULL, 90),
          ($2, $3, 'Any plant', 'taxonomy', NULL, 'Plantae', 1)
        `,
        [exactItemId, taxonomyItemId, levelId, speciesId],
      );
      await client.queryArray(
        `
        INSERT INTO public.user_field_trips (
          id, user_id, template_id, started_at, current_level_number,
          is_profile_visible, hidden_at
        )
        VALUES ($1, $2, $3, NOW() - INTERVAL '1 hour', 1, TRUE, NULL)
        `,
        [userFieldTripId, userId, templateId],
      );
      await client.queryArray(
        `
        INSERT INTO public.user_field_trip_active_periods (
          user_field_trip_id, started_at
        )
        VALUES ($1, NOW() - INTERVAL '1 hour')
        `,
        [userFieldTripId],
      );

      const fallback = await applyStandardProgressV2(
        client,
        userId,
        scanId,
        null,
        null,
      );
      assertEquals(
        fallback.find((update) => update.template_id === templateId)
          ?.newly_completed_items[0].item_id,
        exactItemId,
      );

      await client.queryArray(
        `DELETE FROM public.user_field_trip_item_completions WHERE user_field_trip_id = $1`,
        [userFieldTripId],
      );

      const preferred = await applyStandardProgressV2(
        client,
        userId,
        scanId,
        userFieldTripId,
        taxonomyItemId,
      );
      assertEquals(
        preferred.find((update) => update.template_id === templateId)
          ?.newly_completed_items[0].item_id,
        taxonomyItemId,
      );

      const completionCount = await client.queryObject<{ count: bigint }>(
        `
        SELECT COUNT(*)::bigint AS count
        FROM public.user_field_trip_item_completions
        WHERE user_field_trip_id = $1 AND scan_id = $2
        `,
        [userFieldTripId, scanId],
      );
      assertEquals(completionCount.rows[0].count, 1n);
    },
  );
});

async function applyStandardProgress(
  client: Client,
  userId: string,
  scanId: string,
): Promise<StandardProgressUpdate[]> {
  const result = await client.queryObject<{ data: StandardProgressUpdate[] }>(
    `SELECT public.apply_field_trip_scan_progress($1, $2)::jsonb AS data`,
    [userId, scanId],
  );
  return result.rows[0].data;
}

async function applyStandardProgressV2(
  client: Client,
  userId: string,
  scanId: string,
  preferredUserFieldTripId: string | null,
  preferredItemId: string | null,
): Promise<StandardProgressUpdate[]> {
  const result = await client.queryObject<{ data: StandardProgressUpdate[] }>(
    `
    SELECT public.apply_field_trip_scan_progress_v2(
      $1, $2, $3::uuid, $4::uuid
    )::jsonb AS data
    `,
    [userId, scanId, preferredUserFieldTripId, preferredItemId],
  );
  return result.rows[0].data;
}

async function getScanContributions(
  client: Client,
  userId: string,
  scanId: string,
): Promise<ScanContribution[]> {
  const result = await client.queryObject<{ data: ScanContribution[] }>(
    `SELECT public.get_field_trip_scan_contributions($1, $2)::jsonb AS data`,
    [userId, scanId],
  );
  return result.rows[0].data;
}

async function applyChallengeProgress(
  client: Client,
  userId: string,
  scanId: string,
): Promise<ChallengeProgressUpdate[]> {
  const result = await client.queryObject<{ data: ChallengeProgressUpdate[] }>(
    `SELECT public.apply_field_trip_challenge_scan_progress($1, $2)::jsonb AS data`,
    [userId, scanId],
  );
  return result.rows[0].data;
}

function assertCreditedUpdate(
  update: StandardProgressUpdate | ChallengeProgressUpdate,
  expectedLevel: number,
  expectedItemId: string,
): void {
  assertEquals(update.credited_level_number, expectedLevel);
  assertEquals(update.credited_completed_count, 1);
  assertEquals(update.credited_target_count, 1);
  assertEquals(update.newly_completed_items.map((item) => item.item_id), [
    expectedItemId,
  ]);
  assertEquals(update.removed_item_ids, []);
}

function assertCorrectionRemoval(
  update: StandardProgressUpdate | ChallengeProgressUpdate,
  expectedLevel: number,
  expectedRemovedItemId: string,
): void {
  assertEquals(update.current_level_number, expectedLevel);
  assertEquals(update.credited_level_number, expectedLevel);
  assertEquals(update.credited_completed_count, 0);
  assertEquals(update.credited_target_count, 1);
  assertEquals(update.newly_completed_items, []);
  assertEquals(update.removed_item_ids, [expectedRemovedItemId]);
}
