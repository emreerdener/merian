import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type AtomicFixture = {
  userId: string;
  speciesId: string;
  scanId: string;
  tripId: string;
  itemId: string;
  challengeId: string;
};

Deno.test("scan ingestion atomically applies standard, Event, preference, and achievement progress", async () => {
  await withExploreDbTest(
    "fieldTripAtomicProgressDb.test",
    async (client: Client) => {
      const fixture = await insertAtomicFixture(client, false);
      await client.queryArray(
        `
          INSERT INTO public.scan_ingestion_intents(
            scan_id, user_id, endpoint, request_payload
          )
          VALUES (
            $1, $2, 'identify-multimodal',
            JSONB_BUILD_OBJECT(
              'preferredGoal', JSONB_BUILD_OBJECT(
                'userFieldTripId', $3::TEXT,
                'itemId', $4::TEXT
              )
            )
          )
        `,
        [fixture.scanId, fixture.userId, fixture.tripId, fixture.itemId],
      );
      await insertScan(client, {
        id: fixture.scanId,
        userId: fixture.userId,
        speciesId: fixture.speciesId,
        confirmedSpeciesId: fixture.speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
      });

      const receipt = await client.queryObject<{
        result: {
          field_trip_updates: Array<{ user_field_trip_id: string }>;
          challenge_updates: Array<{ challenge_id: string }>;
          first_field_trip_achievement: { kind: string };
          first_field_trip_achievement_newly_unlocked: boolean;
        };
        preferred_user_field_trip_id: string;
        preferred_item_id: string;
      }>(
        `
          SELECT result, preferred_user_field_trip_id::TEXT,
                 preferred_item_id::TEXT
          FROM public.field_trip_scan_progress_receipts
          WHERE scan_id = $1
        `,
        [fixture.scanId],
      );

      assertEquals(
        receipt.rows[0].preferred_user_field_trip_id,
        fixture.tripId,
      );
      assertEquals(receipt.rows[0].preferred_item_id, fixture.itemId);
      assertEquals(
        receipt.rows[0].result.field_trip_updates[0].user_field_trip_id,
        fixture.tripId,
      );
      assertEquals(
        receipt.rows[0].result.challenge_updates[0].challenge_id,
        fixture.challengeId,
      );
      assertEquals(
        receipt.rows[0].result.first_field_trip_achievement.kind,
        "seasonal_challenge",
      );
      assertEquals(
        receipt.rows[0].result.first_field_trip_achievement_newly_unlocked,
        true,
      );

      const retry = await client.queryObject<
        { data: typeof receipt.rows[0]["result"] }
      >(
        `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4) AS data`,
        [fixture.userId, fixture.scanId, fixture.tripId, fixture.itemId],
      );
      assertEquals(retry.rows[0].data, receipt.rows[0].result);
    },
  );
});

Deno.test("Event failure rolls back standard progress and preference persistence", async () => {
  await withExploreDbTest(
    "fieldTripAtomicProgressDb.test",
    async (client: Client) => {
      const fixture = await insertAtomicFixture(client, true);
      await client.queryArray("SAVEPOINT before_atomic_failure");
      await client.queryArray(
        `
          CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress(
            self_id UUID,
            target_scan_id UUID
          )
          RETURNS JSONB
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $failure$
          BEGIN
            RAISE EXCEPTION 'forced Event progress failure';
          END;
          $failure$
        `,
      );

      let failed = false;
      try {
        await client.queryArray(
          `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4)`,
          [fixture.userId, fixture.scanId, fixture.tripId, fixture.itemId],
        );
      } catch {
        failed = true;
      }
      assert(failed);
      await client.queryArray("ROLLBACK TO SAVEPOINT before_atomic_failure");

      const state = await client.queryObject<{
        standard_count: number;
        preference_count: number;
        receipt_count: number;
      }>(
        `
          SELECT
            (SELECT COUNT(*)::INTEGER FROM public.user_field_trip_item_completions WHERE scan_id = $1) AS standard_count,
            (SELECT COUNT(*)::INTEGER FROM public.field_trip_scan_goal_preferences WHERE scan_id = $1) AS preference_count,
            (SELECT COUNT(*)::INTEGER FROM public.field_trip_scan_progress_receipts WHERE scan_id = $1) AS receipt_count
        `,
        [fixture.scanId],
      );
      assertEquals(state.rows[0], {
        standard_count: 0,
        preference_count: 0,
        receipt_count: 0,
      });
    },
  );
});

async function insertAtomicFixture(
  client: Client,
  insertScanBeforeProgress: boolean,
): Promise<AtomicFixture> {
  const userId = crypto.randomUUID();
  const speciesId = crypto.randomUUID();
  const scanId = crypto.randomUUID();
  const templateId = crypto.randomUUID();
  const levelId = crypto.randomUUID();
  const itemId = crypto.randomUUID();
  const tripId = crypto.randomUUID();
  const challengeId = crypto.randomUUID();
  const participationId = crypto.randomUUID();

  await insertUser(client, userId, `Atomic Progress ${userId}`);
  await insertSpecies(
    client,
    speciesId,
    `Testus atomicus ${templateId.slice(0, 8)}`,
  );
  await client.queryArray(
    `
      INSERT INTO public.field_trip_templates(
        id, slug, title, difficulty, is_pro_only, is_rotating_free,
        is_active, sort_order
      )
      VALUES ($1, $2, 'Atomic fixture', 'starter', FALSE, FALSE, TRUE, 999)
    `,
    [templateId, `atomic_${templateId.slice(0, 8)}`],
  );
  await client.queryArray(
    `INSERT INTO public.field_trip_levels(id, template_id, level_number, title) VALUES ($1, $2, 1, 'Level 1')`,
    [levelId, templateId],
  );
  await client.queryArray(
    `
      INSERT INTO public.field_trip_checklist_items(
        id, level_id, prompt, match_type, species_id, sort_order
      )
      VALUES ($1, $2, 'Atomic species', 'species', $3, 1)
    `,
    [itemId, levelId, speciesId],
  );
  await client.queryArray(
    `
      INSERT INTO public.user_field_trips(
        id, user_id, template_id, started_at, current_level_number,
        is_profile_visible
      )
      VALUES ($1, $2, $3, NOW() - INTERVAL '1 hour', 1, TRUE)
    `,
    [tripId, userId, templateId],
  );
  await client.queryArray(
    `INSERT INTO public.user_field_trip_active_periods(user_field_trip_id, started_at) VALUES ($1, NOW() - INTERVAL '1 hour')`,
    [tripId],
  );
  await client.queryArray(
    `
      INSERT INTO public.field_trip_challenges(
        id, template_id, slug, title, starts_at, ends_at, is_active
      )
      VALUES ($1, $2, $3, 'Atomic Event', NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day', TRUE)
    `,
    [challengeId, templateId, `atomic_event_${challengeId.slice(0, 8)}`],
  );
  await client.queryArray(
    `
      INSERT INTO public.field_trip_challenge_participants(
        id, challenge_id, user_id, user_field_trip_id, joined_at,
        current_level_number
      )
      VALUES ($1, $2, $3, $4, NOW() - INTERVAL '1 hour', 1)
    `,
    [participationId, challengeId, userId, tripId],
  );

  if (insertScanBeforeProgress) {
    await insertScan(client, {
      id: scanId,
      userId,
      speciesId,
      confirmedSpeciesId: speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "private",
    });
  }

  return { userId, speciesId, scanId, tripId, itemId, challengeId };
}

Deno.test("presence and Human confidence cannot qualify as Field Trip taxon evidence", async () => {
  await withExploreDbTest("fieldTripAudioSubjectDb", async (client) => {
    const denied = [
      ["unresolved presence", "species_id = NULL, confirmed_species_id = NULL"],
      ["non-biological source", "is_biological_subject = FALSE"],
      ...[
        "human",
        "humans",
        "human being",
        "person",
        "human breathing",
        "human speech",
        "human vocalisation",
        "human vocalization",
        "homo sapiens",
        "homo sapien",
      ].map((name) => [name, `user_identification_override = '${name}'`]),
    ];
    for (const [label, mutation] of denied) {
      const fixture = await insertAtomicFixture(client, true);
      await client.queryArray(
        `UPDATE public.scans SET ai_confidence_score = 1, user_confirmed_identification = TRUE, ${mutation} WHERE id = $1`,
        [fixture.scanId],
      );
      await client.queryArray(
        `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4)`,
        [fixture.userId, fixture.scanId, fixture.tripId, fixture.itemId],
      );
      const state = await contributionState(client, fixture);
      assertEquals(state.standard_count, 0, label);
      assertEquals(state.challenge_count, 0, label);
    }
    // Make the goal itself match Human: failure must come from subject eligibility,
    // not an incidental mismatch between the scan and checklist species.
    const human = await insertAtomicFixture(client, true);
    await client.queryArray(
      `UPDATE public.species_dictionary SET scientific_name = 'Homo sapiens' WHERE id = $1`,
      [human.speciesId],
    );
    await client.queryArray(
      `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4)`,
      [human.userId, human.scanId, human.tripId, human.itemId],
    );
    assertEquals((await contributionState(client, human)).standard_count, 0);
    assertEquals((await contributionState(client, human)).challenge_count, 0);
  });
});

Deno.test("Human override withdraws completed standard and Event credit and invalidates its receipt", async () => {
  await withExploreDbTest("fieldTripHumanOverrideDb", async (client) => {
    const fixture = await insertAtomicFixture(client, true);
    await client.queryArray(
      `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4)`,
      [fixture.userId, fixture.scanId, fixture.tripId, fixture.itemId],
    );
    const before = await contributionState(client, fixture);
    assertEquals(before.standard_count, 1);
    assertEquals(before.challenge_count, 1);
    assertEquals(before.trip_complete, true);
    assertEquals(before.challenge_complete, true);
    await client.queryArray(
      `UPDATE public.scans SET user_identification_override = $2 WHERE id = $1`,
      [fixture.scanId, " \tHuman   speech\n"],
    );
    await assertWithdrawnSubject(client, fixture);
    const first = await client.queryObject<{ data: unknown }>(
      `SELECT public.apply_field_trip_scan_progress_atomic($1, $2) AS data`,
      [fixture.userId, fixture.scanId],
    );
    const retry = await client.queryObject<{ data: unknown }>(
      `SELECT public.apply_field_trip_scan_progress_atomic($1, $2) AS data`,
      [fixture.userId, fixture.scanId],
    );
    assertEquals(retry.rows, first.rows);
    await client.queryArray(
      `UPDATE public.scans SET user_identification_override = NULL WHERE id = $1`,
      [fixture.scanId],
    );
    assertEquals((await contributionState(client, fixture)).standard_count, 1);
    assertEquals((await contributionState(client, fixture)).challenge_count, 1);
  });
});

Deno.test("subject migration repairs historical credit with or without a receipt", async (t) => {
  for (const receiptExists of [true, false]) {
    await t.step(
      receiptExists ? "old receipt" : "only saved preference",
      async () => {
        await withExploreDbTest("fieldTripSubjectRepairDb", async (client) => {
          const fixture = await insertAtomicFixture(client, true);
          await client.queryArray(
            `SELECT public.apply_field_trip_scan_progress_atomic($1, $2, $3, $4)`,
            [fixture.userId, fixture.scanId, fixture.tripId, fixture.itemId],
          );
          // Reproduce pre-migration state: the old trigger did not observe override-only edits.
          await client.queryArray(
            `ALTER TABLE public.scans DISABLE TRIGGER trg_apply_ingested_scan_field_trip_progress_update`,
          );
          await client.queryArray(
            `UPDATE public.scans SET user_identification_override = 'Human vocalization' WHERE id = $1`,
            [fixture.scanId],
          );
          await client.queryArray(
            receiptExists
              ? `UPDATE public.field_trip_scan_progress_receipts SET scan_revision = scan_revision - 'user_identification_override' WHERE scan_id = $1`
              : `DELETE FROM public.field_trip_scan_progress_receipts WHERE scan_id = $1`,
            [fixture.scanId],
          );
          assertEquals(
            (await contributionState(client, fixture)).standard_count,
            1,
          );
          const migration = await Deno.readTextFile(
            new URL(
              "../../migrations/20260924062640_gate_field_trip_progress_by_subject.sql",
              import.meta.url,
            ),
          );
          await client.queryArray(migration);
          await assertWithdrawnSubject(client, fixture);
          await client.queryArray(
            `UPDATE public.scans SET user_identification_override = NULL WHERE id = $1`,
            [fixture.scanId],
          );
          const restored = await contributionState(client, fixture);
          assertEquals(restored.standard_count, 1);
          assertEquals(restored.challenge_count, 1);
          const receipt = await client.queryObject<
            { trip: string; item: string }
          >(
            `SELECT preferred_user_field_trip_id::TEXT AS trip, preferred_item_id::TEXT AS item FROM public.field_trip_scan_progress_receipts WHERE scan_id = $1`,
            [fixture.scanId],
          );
          assertEquals(receipt.rows[0], {
            trip: fixture.tripId,
            item: fixture.itemId,
          });
        });
      },
    );
  }
});

async function contributionState(client: Client, fixture: AtomicFixture) {
  const result = await client.queryObject<{
    standard_count: number;
    challenge_count: number;
    trip_complete: boolean;
    challenge_complete: boolean;
    badge_count: number;
    preference_count: number;
  }>(
    `SELECT
      (SELECT COUNT(*)::INTEGER FROM public.user_field_trip_item_completions WHERE scan_id = $1) AS standard_count,
      (SELECT COUNT(*)::INTEGER FROM public.field_trip_challenge_item_completions WHERE scan_id = $1) AS challenge_count,
      (SELECT completed_at IS NOT NULL FROM public.user_field_trips WHERE id = $2) AS trip_complete,
      (SELECT completed_at IS NOT NULL FROM public.field_trip_challenge_participants WHERE challenge_id = $3 AND user_id = $4) AS challenge_complete,
      (SELECT COUNT(*)::INTEGER FROM public.field_trip_challenge_badges WHERE user_id = $4 AND challenge_id = $3) AS badge_count,
      (SELECT COUNT(*)::INTEGER FROM public.field_trip_scan_goal_preferences WHERE scan_id = $1) AS preference_count`,
    [fixture.scanId, fixture.tripId, fixture.challengeId, fixture.userId],
  );
  return result.rows[0];
}

async function assertWithdrawnSubject(client: Client, fixture: AtomicFixture) {
  assertEquals(await contributionState(client, fixture), {
    standard_count: 0,
    challenge_count: 0,
    trip_complete: false,
    challenge_complete: false,
    badge_count: 0,
    preference_count: 1,
  });
  const receipt = await client.queryObject<
    {
      revision: string;
      override: string;
      unlocked: boolean;
      trip: string;
      item: string;
    }
  >(
    `SELECT scan_revision ->> 'user_identification_override' AS revision,
      (SELECT user_identification_override FROM public.scans WHERE id = $1) AS override,
      (result ->> 'first_field_trip_achievement_newly_unlocked')::BOOLEAN AS unlocked,
      preferred_user_field_trip_id::TEXT AS trip, preferred_item_id::TEXT AS item
     FROM public.field_trip_scan_progress_receipts WHERE scan_id = $1`,
    [fixture.scanId],
  );
  assertEquals(receipt.rows[0].revision, receipt.rows[0].override);
  assertEquals(receipt.rows[0].unlocked, false);
  assertEquals(receipt.rows[0].trip, fixture.tripId);
  assertEquals(receipt.rows[0].item, fixture.itemId);
}
