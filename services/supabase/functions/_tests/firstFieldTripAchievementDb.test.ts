import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser, withExploreDbTest } from "./exploreDbTestHelpers.ts";

type AchievementProgress = {
  kind: "standard_outing" | "seasonal_challenge";
  completed_at: string;
  template_slug: string | null;
  challenge_id: string | null;
};

type PublicAward = {
  type: string;
  current_count: number;
  last_interaction_at: string | null;
};

Deno.test("First Field trip achievement selects earliest completion with deterministic challenge ties", async () => {
  await withExploreDbTest(
    "firstFieldTripAchievementDb.test",
    async (client: Client) => {
      const userId = crypto.randomUUID();
      const templateId = crypto.randomUUID();
      const tripId = crypto.randomUUID();
      const challengeId = crypto.randomUUID();
      const participantId = crypto.randomUUID();
      const suffix = templateId.slice(0, 8);

      await insertUser(client, userId, "Field Naturalist");
      await client.queryArray(
        `
        INSERT INTO public.field_trip_templates (
          id, slug, title, difficulty, is_pro_only, is_rotating_free,
          is_active, sort_order
        )
        VALUES ($1, $2, 'Achievement fixture', 'starter', FALSE, FALSE, TRUE, 999)
        `,
        [templateId, `achievement_fixture_${suffix}`],
      );
      await client.queryArray(
        `
        INSERT INTO public.user_field_trips (
          id, user_id, template_id, completed_at
        )
        VALUES ($1, $2, $3, '2026-07-18T10:00:00Z')
        `,
        [tripId, userId, templateId],
      );

      let progress = await getProgress(client, userId);
      assertEquals(progress?.kind, "standard_outing");
      assertEquals(progress?.template_slug, `achievement_fixture_${suffix}`);

      await client.queryArray(
        `
        INSERT INTO public.field_trip_challenges (
          id, template_id, slug, title, starts_at, ends_at, is_active
        )
        VALUES (
          $1, $2, $3, 'Achievement challenge',
          '2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z', TRUE
        )
        `,
        [challengeId, templateId, `achievement_challenge_${suffix}`],
      );
      await client.queryArray(
        `
        INSERT INTO public.field_trip_challenge_participants (
          id, challenge_id, user_id, user_field_trip_id, completed_at
        )
        VALUES ($1, $2, $3, $4, '2026-07-18T09:00:00Z')
        `,
        [participantId, challengeId, userId, tripId],
      );

      progress = await getProgress(client, userId);
      assertEquals(progress?.kind, "seasonal_challenge");
      assertEquals(progress?.challenge_id, challengeId);

      await client.queryArray(
        `
        UPDATE public.user_field_trips
        SET completed_at = '2026-07-18T08:00:00Z'
        WHERE id = $1
        `,
        [tripId],
      );
      progress = await getProgress(client, userId);
      assertEquals(progress?.kind, "standard_outing");

      await client.queryArray(
        `
        UPDATE public.user_field_trips
        SET completed_at = '2026-07-18T07:00:00Z'
        WHERE id = $1
        `,
        [tripId],
      );
      await client.queryArray(
        `
        UPDATE public.field_trip_challenge_participants
        SET completed_at = '2026-07-18T07:00:00Z'
        WHERE id = $1
        `,
        [participantId],
      );
      progress = await getProgress(client, userId);
      assertEquals(progress?.kind, "seasonal_challenge");
      assertEquals(progress?.challenge_id, challengeId);

      const profileResult = await client.queryObject<{ awards: PublicAward[] }>(
        `
        SELECT awards
        FROM public.get_explore_author_profile($1, $1, 9)
        `,
        [userId],
      );
      const publicAward = profileResult.rows[0].awards.find((award) =>
        award.type === "first_field_trip"
      );
      assert(publicAward);
      assertEquals(publicAward.current_count, 1);
      assert(
        publicAward.last_interaction_at?.startsWith("2026-07-18T07:00:00"),
      );

      const indexResult = await client.queryObject<{ indexname: string }>(
        `
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname IN (
            'idx_user_field_trips_user_completed_at',
            'idx_field_trip_challenge_participants_user_completed_at'
          )
        ORDER BY indexname
        `,
      );
      assertEquals(indexResult.rows.map((row) => row.indexname), [
        "idx_field_trip_challenge_participants_user_completed_at",
        "idx_user_field_trips_user_completed_at",
      ]);

      const privileges = await client.queryObject<{
        anon: boolean;
        authenticated: boolean;
        service_role: boolean;
      }>(
        `
        SELECT
          has_function_privilege('anon', 'public.get_first_field_trip_achievement_progress(uuid)', 'EXECUTE') AS anon,
          has_function_privilege('authenticated', 'public.get_first_field_trip_achievement_progress(uuid)', 'EXECUTE') AS authenticated,
          has_function_privilege('service_role', 'public.get_first_field_trip_achievement_progress(uuid)', 'EXECUTE') AS service_role
        `,
      );
      assertEquals(privileges.rows[0], {
        anon: false,
        authenticated: false,
        service_role: true,
      });

      await client.queryArray("SAVEPOINT authenticated_execution");
      await client.queryArray("SET LOCAL ROLE authenticated");
      let authenticatedWasDenied = false;
      try {
        await getProgress(client, userId);
      } catch {
        authenticatedWasDenied = true;
      }
      await client.queryArray("ROLLBACK TO SAVEPOINT authenticated_execution");
      await client.queryArray("RELEASE SAVEPOINT authenticated_execution");
      assert(
        authenticatedWasDenied,
        "authenticated role must not execute the progress RPC",
      );

      await client.queryArray("SET LOCAL ROLE service_role");
      progress = await getProgress(client, userId);
      assertEquals(progress?.kind, "seasonal_challenge");
      await client.queryArray("RESET ROLE");
    },
  );
});

async function getProgress(
  client: Client,
  userId: string,
): Promise<AchievementProgress | null> {
  const result = await client.queryObject<{ data: AchievementProgress | null }>(
    `
    SELECT public.get_first_field_trip_achievement_progress($1)::jsonb AS data
    `,
    [userId],
  );
  return result.rows[0].data;
}
