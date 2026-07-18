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
};

type ChallengeProgressUpdate = {
  participation_id: string;
  challenge_id: string;
  current_level_number: number;
  credited_level_number: number;
  credited_completed_count: number;
  credited_target_count: number;
  newly_completed_items: ProgressItem[];
};

Deno.test("Field trip credited progress only returns rows inserted by the current attempt", async () => {
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
          NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day',
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
          firstStandardFixture.user_field_trip_id,
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
      assertCreditedUpdate(secondStandardFixtures[0], 2, secondItemId);

      const secondChallenge = await applyChallengeProgress(
        client,
        userId,
        scanId,
      );
      const secondChallengeFixtures = secondChallenge.filter((update) =>
        update.challenge_id === challengeId
      );
      assertEquals(secondChallengeFixtures.length, 1);
      assertCreditedUpdate(secondChallengeFixtures[0], 2, secondItemId);

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
}
