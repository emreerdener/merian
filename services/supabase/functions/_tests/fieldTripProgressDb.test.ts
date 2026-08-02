import { assert, assertEquals } from "@std/assert";
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

type CatalogGoalMatchInput = {
  templateSlug: "backyard_safari" | "park_pollinators";
  prompt: string;
  scientificName: string;
  commonName: string;
  kingdom: string;
  phylum?: string;
  className?: string;
  order?: string;
  family?: string;
  genus?: string;
  ecologyType?: string;
  habitatDescription?: string;
  groupTags?: string[];
};

Deno.test("Field trip evidence uses Possible-match tier boundaries and review overrides", async () => {
  await withExploreDbTest(
    "fieldTripConfidencePolicyDb.test",
    async (client: Client) => {
      const correctedSpeciesId = crypto.randomUUID();
      const result = await client.queryObject<{
        weak_flash: boolean;
        possible_flash: boolean;
        weak_pro: boolean;
        possible_pro: boolean;
        unknown_tier_uses_flash: boolean;
        ai_confirmation_overrides_score: boolean;
        correction_overrides_score: boolean;
      }>(
        `
          SELECT
            public.field_trip_scan_identification_is_eligible(
              0.749::DOUBLE PRECISION, 'flash', NULL, FALSE
            ) AS weak_flash,
            public.field_trip_scan_identification_is_eligible(
              0.75::DOUBLE PRECISION, 'flash', NULL, FALSE
            ) AS possible_flash,
            public.field_trip_scan_identification_is_eligible(
              0.649::DOUBLE PRECISION, 'pro', NULL, FALSE
            ) AS weak_pro,
            public.field_trip_scan_identification_is_eligible(
              0.65::DOUBLE PRECISION, 'pro', NULL, FALSE
            ) AS possible_pro,
            public.field_trip_scan_identification_is_eligible(
              0.70::DOUBLE PRECISION, 'future-tier', NULL, FALSE
            ) AS unknown_tier_uses_flash,
            public.field_trip_scan_identification_is_eligible(
              0.25::DOUBLE PRECISION, 'flash', NULL, TRUE
            ) AS ai_confirmation_overrides_score,
            public.field_trip_scan_identification_is_eligible(
              0.25::DOUBLE PRECISION, 'flash', $1::UUID, FALSE
            ) AS correction_overrides_score
        `,
        [correctedSpeciesId],
      );

      assertEquals(result.rows[0], {
        weak_flash: false,
        possible_flash: true,
        weak_pro: false,
        possible_pro: true,
        unknown_tier_uses_flash: false,
        ai_confirmation_overrides_score: true,
        correction_overrides_score: true,
      });
    },
  );
});

Deno.test("Weak Field trip matches wait for explicit identification confirmation", async () => {
  await withExploreDbTest(
    "fieldTripWeakMatchConfirmationDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const templateId = crypto.randomUUID();
      const levelId = crypto.randomUUID();
      const itemId = crypto.randomUUID();
      const userFieldTripId = crypto.randomUUID();
      const challengeId = crypto.randomUUID();
      const participationId = crypto.randomUUID();
      const suffix = templateId.slice(0, 8);

      await insertUser(client, userId, "Weak Match Viewer");
      await insertSpecies(
        client,
        speciesId,
        `Testus weakmatchus ${suffix}`,
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_templates (
            id, slug, title, difficulty, is_pro_only, is_rotating_free,
            is_active, sort_order
          )
          VALUES (
            $1, $2, 'Weak match fixture', 'starter',
            FALSE, FALSE, TRUE, 997
          )
        `,
        [templateId, `weak_match_${suffix}`],
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_levels (
            id, template_id, level_number, title
          )
          VALUES ($1, $2, 1, 'Weak match level')
        `,
        [levelId, templateId],
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_checklist_items (
            id, level_id, prompt, match_type, species_id, sort_order
          )
          VALUES ($1, $2, 'Weak match species', 'species', $3, 1)
        `,
        [itemId, levelId, speciesId],
      );
      await client.queryArray(
        `
          INSERT INTO public.user_field_trips (
            id, user_id, template_id, started_at, current_level_number,
            is_profile_visible
          )
          VALUES (
            $1, $2, $3, NOW() - INTERVAL '1 hour', 1, TRUE
          )
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
      await client.queryArray(
        `
          INSERT INTO public.field_trip_challenges (
            id, template_id, slug, title, starts_at, ends_at, is_active
          )
          VALUES (
            $1, $2, $3, 'Weak match Event',
            NOW() - INTERVAL '1 day',
            NOW() + INTERVAL '1 day',
            TRUE
          )
        `,
        [challengeId, templateId, `weak_match_event_${suffix}`],
      );
      await client.queryArray(
        `
          INSERT INTO public.field_trip_challenge_participants (
            id, challenge_id, user_id, user_field_trip_id, joined_at,
            current_level_number
          )
          VALUES (
            $1, $2, $3, $4, NOW() - INTERVAL '1 hour', 1
          )
        `,
        [
          participationId,
          challengeId,
          userId,
          userFieldTripId,
        ],
      );
      await client.queryArray(
        `
          INSERT INTO public.scan_ingestion_intents (
            scan_id, user_id, endpoint, request_payload
          )
          VALUES (
            $1,
            $2,
            'identify-multimodal',
            JSONB_BUILD_OBJECT(
              'preferred_goal',
              JSONB_BUILD_OBJECT(
                'user_field_trip_id', $3::TEXT,
                'item_id', $4::TEXT
              )
            )
          )
        `,
        [scanId, userId, userFieldTripId, itemId],
      );

      await insertScan(client, {
        id: scanId,
        userId,
        speciesId,
        aiConfidenceScore: 0.25,
        inferenceTier: "flash",
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });

      const beforeConfirmation = await client.queryObject<{
        field_trip_updates: StandardProgressUpdate[];
        challenge_updates: ChallengeProgressUpdate[];
        scan_revision: {
          ai_confidence_score: number;
          inference_tier: string;
          user_confirmed_identification: boolean;
        };
        preferred_user_field_trip_id: string;
        preferred_item_id: string;
        standard_count: number;
        challenge_count: number;
      }>(
        `
          SELECT
            receipt.result -> 'field_trip_updates'
              AS field_trip_updates,
            receipt.result -> 'challenge_updates'
              AS challenge_updates,
            receipt.scan_revision,
            receipt.preferred_user_field_trip_id,
            receipt.preferred_item_id,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.user_field_trip_item_completions
              WHERE scan_id = $1
            ) AS standard_count,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.field_trip_challenge_item_completions
              WHERE scan_id = $1
            ) AS challenge_count
          FROM public.field_trip_scan_progress_receipts AS receipt
          WHERE receipt.scan_id = $1
        `,
        [scanId],
      );
      assertEquals(beforeConfirmation.rows[0].field_trip_updates, []);
      assertEquals(beforeConfirmation.rows[0].challenge_updates, []);
      assertEquals(beforeConfirmation.rows[0].standard_count, 0);
      assertEquals(beforeConfirmation.rows[0].challenge_count, 0);
      assertEquals(
        beforeConfirmation.rows[0].preferred_user_field_trip_id,
        userFieldTripId,
      );
      assertEquals(beforeConfirmation.rows[0].preferred_item_id, itemId);
      assertEquals(
        beforeConfirmation.rows[0].scan_revision.ai_confidence_score,
        0.25,
      );
      assertEquals(
        beforeConfirmation.rows[0].scan_revision.inference_tier,
        "flash",
      );
      assertEquals(
        beforeConfirmation.rows[0].scan_revision
          .user_confirmed_identification,
        false,
      );

      await client.queryArray(
        `
          UPDATE public.scan_ingestion_intents
          SET request_payload = '{}'::JSONB
          WHERE scan_id = $1
            AND user_id = $2
        `,
        [scanId, userId],
      );
      await client.queryArray(
        `
          UPDATE public.scans
          SET user_confirmed_identification = TRUE,
              user_review_state = 'ai_confirmed'
          WHERE id = $1
        `,
        [scanId],
      );

      const afterConfirmation = await client.queryObject<{
        field_trip_updates: StandardProgressUpdate[];
        challenge_updates: ChallengeProgressUpdate[];
        user_confirmed_identification: boolean;
        preferred_user_field_trip_id: string;
        preferred_item_id: string;
        standard_count: number;
        challenge_count: number;
      }>(
        `
          SELECT
            receipt.result -> 'field_trip_updates'
              AS field_trip_updates,
            receipt.result -> 'challenge_updates'
              AS challenge_updates,
            (
              receipt.scan_revision
                ->> 'user_confirmed_identification'
            )::BOOLEAN AS user_confirmed_identification,
            receipt.preferred_user_field_trip_id,
            receipt.preferred_item_id,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.user_field_trip_item_completions
              WHERE scan_id = $1
            ) AS standard_count,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.field_trip_challenge_item_completions
              WHERE scan_id = $1
            ) AS challenge_count
          FROM public.field_trip_scan_progress_receipts AS receipt
          WHERE receipt.scan_id = $1
        `,
        [scanId],
      );
      const confirmed = afterConfirmation.rows[0];
      assertEquals(
        confirmed.field_trip_updates[0].newly_completed_items.map((item) =>
          item.item_id
        ),
        [itemId],
      );
      assertEquals(
        confirmed.challenge_updates[0].newly_completed_items.map((item) =>
          item.item_id
        ),
        [itemId],
      );
      assertEquals(confirmed.user_confirmed_identification, true);
      assertEquals(
        confirmed.preferred_user_field_trip_id,
        userFieldTripId,
      );
      assertEquals(confirmed.preferred_item_id, itemId);
      assertEquals(confirmed.standard_count, 1);
      assertEquals(confirmed.challenge_count, 1);

      await client.queryArray(
        `
          UPDATE public.scans
          SET user_confirmed_identification = FALSE,
              confirmed_species_id = NULL,
              user_review_state = 'unreviewed'
          WHERE id = $1
        `,
        [scanId],
      );

      const afterDowngrade = await client.queryObject<{
        field_trip_updates: StandardProgressUpdate[];
        challenge_updates: ChallengeProgressUpdate[];
        standard_count: number;
        challenge_count: number;
        standard_completed_at: Date | null;
        challenge_completed_at: Date | null;
        badge_count: number;
        preference_count: number;
      }>(
        `
          SELECT
            receipt.result -> 'field_trip_updates'
              AS field_trip_updates,
            receipt.result -> 'challenge_updates'
              AS challenge_updates,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.user_field_trip_item_completions
              WHERE scan_id = $1
            ) AS standard_count,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.field_trip_challenge_item_completions
              WHERE scan_id = $1
            ) AS challenge_count,
            (
              SELECT completed_at
              FROM public.user_field_trips
              WHERE id = $2
            ) AS standard_completed_at,
            (
              SELECT completed_at
              FROM public.field_trip_challenge_participants
              WHERE id = $3
            ) AS challenge_completed_at,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.field_trip_challenge_badges
              WHERE participation_id = $3
            ) AS badge_count,
            (
              SELECT COUNT(*)::INTEGER
              FROM public.field_trip_scan_goal_preferences
              WHERE scan_id = $1
                AND user_id = $4
            ) AS preference_count
          FROM public.field_trip_scan_progress_receipts AS receipt
          WHERE receipt.scan_id = $1
        `,
        [scanId, userFieldTripId, participationId, userId],
      );
      assertEquals(afterDowngrade.rows[0].field_trip_updates, []);
      assertEquals(afterDowngrade.rows[0].challenge_updates, []);
      assertEquals(afterDowngrade.rows[0].standard_count, 0);
      assertEquals(afterDowngrade.rows[0].challenge_count, 0);
      assertEquals(afterDowngrade.rows[0].standard_completed_at, null);
      assertEquals(afterDowngrade.rows[0].challenge_completed_at, null);
      assertEquals(afterDowngrade.rows[0].badge_count, 0);
      assertEquals(afterDowngrade.rows[0].preference_count, 1);
    },
  );
});

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

      const correction = await client.queryObject<{
        field_trip_updates: StandardProgressUpdate[];
        challenge_updates: ChallengeProgressUpdate[];
      }>(
        `
          SELECT
            result -> 'field_trip_updates' AS field_trip_updates,
            result -> 'challenge_updates' AS challenge_updates
          FROM public.field_trip_scan_progress_receipts
          WHERE scan_id = $1
        `,
        [scanId],
      );
      const secondStandardFixtures = correction.rows[0].field_trip_updates
        .filter((update) => update.template_id === templateId);
      assertEquals(secondStandardFixtures.length, 1);
      assertCorrectionRemoval(secondStandardFixtures[0], 1, firstItemId);

      const secondChallengeFixtures = correction.rows[0].challenge_updates
        .filter((update) => update.challenge_id === challengeId);
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

Deno.test("Park Pollinators Bee or wasp rejects ants and sawflies", async () => {
  await withExploreDbTest(
    "fieldTripBeeWaspTaxonomyDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const antSpeciesId = crypto.randomUUID();
      const beeSpeciesId = crypto.randomUUID();
      const waspSpeciesId = crypto.randomUUID();
      const sawflySpeciesId = crypto.randomUUID();
      const antScanId = crypto.randomUUID();
      const beeScanId = crypto.randomUUID();
      const userFieldTripId = crypto.randomUUID();

      await insertUser(client, userId, "Bee Wasp Viewer");
      await insertSpecies(client, antSpeciesId, "Dolichoderus bicolor");
      await insertSpecies(client, beeSpeciesId, "Bombus impatiens");
      await insertSpecies(client, waspSpeciesId, "Vespula maculifrons");
      await insertSpecies(client, sawflySpeciesId, "Macremphytus tarsatus");
      await client.queryArray(
        `
        UPDATE public.species_dictionary
        SET kingdom = 'Animalia',
            phylum = 'Arthropoda',
            class = 'Insecta',
            "order" = 'Hymenoptera',
            family = CASE id
              WHEN $1::uuid THEN 'Formicidae'
              WHEN $2::uuid THEN 'Apidae'
              WHEN $3::uuid THEN 'Vespidae'
              WHEN $4::uuid THEN 'Tenthredinidae'
            END,
            genus = CASE id
              WHEN $1::uuid THEN 'Dolichoderus'
              WHEN $2::uuid THEN 'Bombus'
              WHEN $3::uuid THEN 'Vespula'
              WHEN $4::uuid THEN 'Macremphytus'
            END,
            group_tags = CASE id
              WHEN $1::uuid THEN ARRAY['animal', 'insect', 'ant']
              WHEN $2::uuid THEN ARRAY['animal', 'insect', 'bee']
              WHEN $3::uuid THEN ARRAY['animal', 'insect', 'wasp']
              WHEN $4::uuid THEN ARRAY['animal', 'insect', 'sawfly']
            END
        WHERE id = ANY($5::uuid[])
        `,
        [
          antSpeciesId,
          beeSpeciesId,
          waspSpeciesId,
          sawflySpeciesId,
          [antSpeciesId, beeSpeciesId, waspSpeciesId, sawflySpeciesId],
        ],
      );

      const matches = await client.queryObject<{
        species_id: string;
        matches: boolean;
      }>(
        `
        SELECT
          species.id::text AS species_id,
          public.field_trip_item_matches_scan(
            item.match_type,
            item.species_id,
            item.scientific_name,
            item.taxonomy_kingdom,
            item.taxonomy_phylum,
            item.taxonomy_class,
            item.taxonomy_order,
            item.taxonomy_family,
            item.taxonomy_genus,
            item.ecology_type,
            item.habitat_tag,
            item.semantic_tag,
            species.id,
            species.scientific_name,
            species.common_names,
            species.kingdom,
            species.phylum,
            species."class",
            species."order",
            species.family,
            species.genus,
            NULL,
            species.habitat_description,
            species.group_tags
          ) AS matches
        FROM public.field_trip_checklist_items AS item
        JOIN public.field_trip_levels AS level ON level.id = item.level_id
        JOIN public.field_trip_templates AS template ON template.id = level.template_id
        CROSS JOIN public.species_dictionary AS species
        WHERE template.slug = 'park_pollinators'
          AND level.level_number = 1
          AND item.prompt = 'Bee or wasp'
          AND species.id = ANY($1::uuid[])
        ORDER BY species.id
        `,
        [[antSpeciesId, beeSpeciesId, waspSpeciesId, sawflySpeciesId]],
      );

      const matchBySpecies = new Map(
        matches.rows.map((row) => [row.species_id, row.matches]),
      );
      assertEquals(matchBySpecies.get(antSpeciesId), false);
      assertEquals(matchBySpecies.get(beeSpeciesId), true);
      assertEquals(matchBySpecies.get(waspSpeciesId), true);
      assertEquals(matchBySpecies.get(sawflySpeciesId), false);

      const goal = await client.queryObject<{
        template_id: string;
        item_id: string;
      }>(
        `
        SELECT template.id::text AS template_id, item.id::text AS item_id
        FROM public.field_trip_checklist_items AS item
        JOIN public.field_trip_levels AS level ON level.id = item.level_id
        JOIN public.field_trip_templates AS template ON template.id = level.template_id
        WHERE template.slug = 'park_pollinators'
          AND level.level_number = 1
          AND item.prompt = 'Bee or wasp'
        `,
      );
      const { template_id: templateId, item_id: itemId } = goal.rows[0];

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

      await insertScan(client, {
        id: antScanId,
        userId,
        speciesId: antSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      const antProgress = await applyStandardProgress(
        client,
        userId,
        antScanId,
      );
      assertEquals(
        antProgress.some((update) => update.template_id === templateId),
        false,
      );

      await insertScan(client, {
        id: beeScanId,
        userId,
        speciesId: beeSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });
      const beeProgress = await applyStandardProgress(
        client,
        userId,
        beeScanId,
      );
      assertEquals(
        beeProgress.find((update) => update.template_id === templateId)
          ?.newly_completed_items.map((item) => item.item_id),
        [itemId],
      );
    },
  );
});

Deno.test("Active Field Trip goals reject broader taxonomic and ecological lookalikes", async () => {
  await withExploreDbTest(
    "fieldTripNarrowGoalMatchingDb.test",
    async (client: Client) => {
      const cases: Array<{
        label: string;
        expected: boolean;
        input: CatalogGoalMatchInput;
      }> = [
        {
          label: "Backyard Butterfly accepts a butterfly",
          expected: true,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Butterfly",
            scientificName: "Danaus plexippus",
            commonName: "Monarch butterfly",
            kingdom: "Animalia",
            className: "Insecta",
            order: "Lepidoptera",
            groupTags: ["animal", "insect", "butterfly"],
          },
        },
        {
          label: "Backyard Butterfly rejects a moth",
          expected: false,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Butterfly",
            scientificName: "Actias luna",
            commonName: "Luna moth",
            kingdom: "Animalia",
            className: "Insecta",
            order: "Lepidoptera",
            groupTags: ["animal", "insect", "moth"],
          },
        },
        {
          label: "Backyard Spider accepts Araneae",
          expected: true,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Spider",
            scientificName: "Argiope aurantia",
            commonName: "Yellow garden spider",
            kingdom: "Animalia",
            className: "Arachnida",
            order: "Araneae",
          },
        },
        {
          label: "Backyard Spider rejects a tick",
          expected: false,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Spider",
            scientificName: "Amblyomma americanum",
            commonName: "Lone star tick",
            kingdom: "Animalia",
            className: "Arachnida",
            order: "Ixodida",
          },
        },
        {
          label: "Backyard Flowering plant rejects a fern",
          expected: false,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Flowering plant",
            scientificName: "Polystichum acrostichoides",
            commonName: "Christmas fern",
            kingdom: "Plantae",
            className: "Polypodiopsida",
            groupTags: ["plant", "fern"],
          },
        },
        {
          label: "Park Flowering plant accepts a flower",
          expected: true,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Flowering plant",
            scientificName: "Rudbeckia hirta",
            commonName: "Black-eyed Susan",
            kingdom: "Plantae",
            className: "Magnoliopsida",
            groupTags: ["plant", "flower"],
          },
        },
        {
          label: "Domesticated animal accepts a dog",
          expected: true,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Domesticated animal",
            scientificName: "Canis lupus familiaris",
            commonName: "Dog",
            kingdom: "Animalia",
            className: "Mammalia",
            ecologyType: "domesticated",
          },
        },
        {
          label: "Domesticated animal rejects a cultivated plant",
          expected: false,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Domesticated animal",
            scientificName: "Solanum lycopersicum",
            commonName: "Tomato",
            kingdom: "Plantae",
            className: "Magnoliopsida",
            ecologyType: "domesticated",
          },
        },
        {
          label: "Urban wild animal accepts an urban squirrel",
          expected: true,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Urban wild animal",
            scientificName: "Sciurus carolinensis",
            commonName: "Eastern gray squirrel",
            kingdom: "Animalia",
            className: "Mammalia",
            ecologyType: "urban",
          },
        },
        {
          label: "Urban wild animal rejects an urban plant",
          expected: false,
          input: {
            templateSlug: "backyard_safari",
            prompt: "Urban wild animal",
            scientificName: "Taraxacum officinale",
            commonName: "Common dandelion",
            kingdom: "Plantae",
            className: "Magnoliopsida",
            ecologyType: "urban",
          },
        },
        {
          label: "Park Spider rejects a scorpion",
          expected: false,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Spider",
            scientificName: "Centruroides vittatus",
            commonName: "Striped bark scorpion",
            kingdom: "Animalia",
            className: "Arachnida",
            order: "Scorpiones",
          },
        },
        {
          label: "Seed or fruiting plant rejects a fruit fly",
          expected: false,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Seed or fruiting plant",
            scientificName: "Drosophila melanogaster",
            commonName: "Common fruit fly",
            kingdom: "Animalia",
            className: "Insecta",
            order: "Diptera",
            groupTags: ["animal", "insect", "fruit"],
          },
        },
        {
          label: "Seed or fruiting plant accepts a fruit-bearing plant",
          expected: true,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Seed or fruiting plant",
            scientificName: "Malus domestica",
            commonName: "Apple",
            kingdom: "Plantae",
            className: "Magnoliopsida",
            groupTags: ["plant", "fruit"],
          },
        },
        {
          label: "Wild plant rejects a wild deer",
          expected: false,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Wild plant",
            scientificName: "Odocoileus virginianus",
            commonName: "White-tailed deer",
            kingdom: "Animalia",
            className: "Mammalia",
            ecologyType: "wild",
          },
        },
        {
          label: "Wild plant accepts a wild plant",
          expected: true,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Wild plant",
            scientificName: "Asclepias tuberosa",
            commonName: "Butterfly weed",
            kingdom: "Plantae",
            className: "Magnoliopsida",
            ecologyType: "wild",
          },
        },
        {
          label: "Meadow plant rejects a meadow animal",
          expected: false,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Meadow plant",
            scientificName: "Sturnella magna",
            commonName: "Eastern meadowlark",
            kingdom: "Animalia",
            className: "Aves",
            habitatDescription: "Grasslands and open meadows",
          },
        },
        {
          label: "Meadow plant accepts a meadow plant",
          expected: true,
          input: {
            templateSlug: "park_pollinators",
            prompt: "Meadow plant",
            scientificName: "Schizachyrium scoparium",
            commonName: "Little bluestem",
            kingdom: "Plantae",
            className: "Liliopsida",
            habitatDescription: "Dry prairie and open meadow habitat",
          },
        },
      ];

      const results: Record<string, boolean> = {};
      for (const testCase of cases) {
        results[testCase.label] = await catalogGoalMatches(
          client,
          testCase.input,
        );
      }

      assertEquals(
        results,
        Object.fromEntries(cases.map((testCase) => [
          testCase.label,
          testCase.expected,
        ])),
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

async function catalogGoalMatches(
  client: Client,
  input: CatalogGoalMatchInput,
): Promise<boolean> {
  const result = await client.queryObject<{ matches: boolean }>(
    `
    SELECT public.field_trip_item_matches_scan(
      item.match_type,
      item.species_id,
      item.scientific_name,
      item.taxonomy_kingdom,
      item.taxonomy_phylum,
      item.taxonomy_class,
      item.taxonomy_order,
      item.taxonomy_family,
      item.taxonomy_genus,
      item.ecology_type,
      item.habitat_tag,
      item.semantic_tag,
      NULL::uuid,
      $3::text,
      jsonb_build_object('en', $4::text),
      $5::text,
      $6::text,
      $7::text,
      $8::text,
      $9::text,
      $10::text,
      $11::text,
      $12::text,
      $13::text[]
    ) AS matches
    FROM public.field_trip_checklist_items AS item
    JOIN public.field_trip_levels AS level ON level.id = item.level_id
    JOIN public.field_trip_templates AS template ON template.id = level.template_id
    WHERE template.slug = $1
      AND item.prompt = $2
    `,
    [
      input.templateSlug,
      input.prompt,
      input.scientificName,
      input.commonName,
      input.kingdom,
      input.phylum ?? null,
      input.className ?? null,
      input.order ?? null,
      input.family ?? null,
      input.genus ?? null,
      input.ecologyType ?? null,
      input.habitatDescription ?? null,
      input.groupTags ?? [],
    ],
  );
  assertEquals(result.rows.length, 1);
  return result.rows[0].matches;
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
