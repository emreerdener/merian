import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

const migrationUrl = new URL(
  "../../migrations/20260731050009_add_community_identification_activity.sql",
  import.meta.url,
);

type ActivityRow = {
  activity_id: string;
  activity_type: "suggestion_burst" | "consensus_changed" | "resolved";
  activity_at: Date;
  suggestion_count: number;
  recent_actor_names: string[];
  consensus_score: number | string | null;
  request_group: string;
};

type ProjectionRow = {
  activity_type: ActivityRow["activity_type"];
  request_generation_at: Date;
  suggestion_count: number;
};

Deno.test("Community Identify activity DB - bursts, milestones, filters, cursor, and lifecycle", async () => {
  await withExploreDbTest(
    "communityIdentificationActivityDb.test",
    async (client: Client) => {
      const installedRows = await client.queryObject<{ installed: boolean }>(
        `
          SELECT pg_catalog.TO_REGCLASS(
            'internal.community_identification_activity_groups'
          ) IS NOT NULL AS installed
        `,
      );
      if (!installedRows.rows[0].installed) {
        // This integration helper may point at a running local catalog whose
        // later media-health migrations have not yet been replayed. Add only
        // the two read-contract columns inside this test's rollback boundary.
        await client.queryArray(`
          ALTER TABLE public.explore_posts
            ADD COLUMN IF NOT EXISTS media_health_status TEXT
              NOT NULL DEFAULT 'healthy';
          ALTER TABLE public.explore_post_media
            ADD COLUMN IF NOT EXISTS health_status TEXT
              NOT NULL DEFAULT 'healthy'
        `);
        await client.queryArray(await Deno.readTextFile(migrationUrl));
      }

      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const actorAId = crypto.randomUUID();
      const actorBId = crypto.randomUUID();
      const actorCId = crypto.randomUUID();
      const actorDId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const requestId = crypto.randomUUID();

      await insertUser(client, ownerId, "Activity Owner");
      await insertUser(client, viewerId, "Activity Viewer");
      await insertUser(client, actorAId, "Actor A");
      await insertUser(client, actorBId, "Actor B");
      await insertUser(client, actorCId, "Actor C");
      await insertUser(client, actorDId, "Actor D");
      await insertSpecies(client, speciesId, "Rosa activitatis");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });
      await insertExplorePost(client, { id: postId, userId: ownerId, scanId });

      const taxonomyRows = await client.queryObject<{ id: string }>(
        `
          SELECT id
          FROM public.refresh_taxonomy_nodes_from_species_dictionary(
            'community-activity-db-test',
            TRUE
          )
        `,
      );
      const taxonomyVersionId = taxonomyRows.rows[0].id;
      const taxonRows = await client.queryObject<{ id: string }>(
        `
          SELECT id
          FROM public.taxon_nodes
          WHERE taxonomy_version_id = $1
            AND species_id = $2
        `,
        [taxonomyVersionId, speciesId],
      );
      const taxonId = taxonRows.rows[0].id;
      const generationAt = "2026-07-30T10:00:00.000Z";

      await client.queryArray(
        `
          INSERT INTO public.explore_community_requests (
            id,
            post_id,
            scan_id,
            requested_by,
            requested_at,
            taxonomy_version_id,
            initial_taxon_node_id
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7)
        `,
        [
          requestId,
          postId,
          scanId,
          ownerId,
          generationAt,
          taxonomyVersionId,
          taxonId,
        ],
      );

      const insertSuggestion = async (
        userId: string,
        createdAt: string,
      ): Promise<string> => {
        const identificationId = crypto.randomUUID();
        await client.queryArray(
          `
            INSERT INTO public.explore_identifications (
              id,
              request_id,
              post_id,
              user_id,
              taxon_node_id,
              taxonomy_version_id,
              created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
          `,
          [
            identificationId,
            requestId,
            postId,
            userId,
            taxonId,
            taxonomyVersionId,
            createdAt,
          ],
        );
        return identificationId;
      };

      const firstIdentificationId = await insertSuggestion(
        actorAId,
        "2026-07-30T10:05:00.000Z",
      );
      await client.queryArray(
        `
          UPDATE public.explore_identifications
          SET withdrawn_at = '2026-07-30T10:10:00.000Z'
          WHERE id = $1
        `,
        [firstIdentificationId],
      );
      await insertSuggestion(actorAId, "2026-07-30T11:05:00.000Z");
      await insertSuggestion(actorDId, "2026-07-30T11:20:00.000Z");
      await insertSuggestion(actorCId, "2026-07-30T11:35:00.000Z");
      await insertSuggestion(actorBId, "2026-07-30T12:05:00.000Z");
      await insertSuggestion(ownerId, "2026-07-30T13:05:01.000Z");

      const burstRows = await client.queryObject<ProjectionRow>(
        `
          SELECT
            activity_group.activity_type,
            activity_group.request_generation_at,
            COALESCE(SUM(activity_actor.suggestion_count), 0)::INTEGER
              AS suggestion_count
          FROM internal.community_identification_activity_groups
            AS activity_group
          LEFT JOIN internal.community_identification_activity_actors
            AS activity_actor
            ON activity_actor.activity_group_id = activity_group.id
          WHERE activity_group.request_id = $1
            AND activity_group.activity_type = 'suggestion_burst'
          GROUP BY
            activity_group.id,
            activity_group.activity_type,
            activity_group.request_generation_at,
            activity_group.activity_at
          ORDER BY activity_group.activity_at
        `,
        [requestId],
      );

      assertEquals(burstRows.rows.length, 2);
      assertEquals(burstRows.rows[0].suggestion_count, 5);
      assertEquals(burstRows.rows[1].suggestion_count, 1);

      // Emulate migration backfill ordering: all suggestions have already
      // advanced the burst before an older consensus event is projected.
      await client.queryArray(
        `
          INSERT INTO public.community_consensus_events (
            id,
            request_id,
            post_id,
            previous_status,
            new_status,
            previous_taxon_node_id,
            new_taxon_node_id,
            previous_rank,
            new_rank,
            new_score,
            reason,
            created_at
          )
          VALUES (
            $1, $2, $3, 'needs_id', 'needs_id', NULL, $4,
            NULL, 'species', 0.44, 'identification_submitted',
            '2026-07-30T12:06:00.000Z'
          )
        `,
        [crypto.randomUUID(), requestId, postId, taxonId],
      );
      await client.queryArray(
        `
          INSERT INTO public.community_consensus_events (
            id,
            request_id,
            post_id,
            previous_status,
            new_status,
            previous_taxon_node_id,
            new_taxon_node_id,
            previous_rank,
            new_rank,
            new_score,
            reason,
            created_at
          )
          VALUES (
            $1, $2, $3, 'needs_id', 'needs_id', NULL, $4,
            NULL, 'species', 0.55, 'identification_submitted',
            '2026-07-30T13:07:00.000Z'
          )
        `,
        [crypto.randomUUID(), requestId, postId, taxonId],
      );
      await client.queryArray(
        `
          INSERT INTO public.community_consensus_events (
            id,
            request_id,
            post_id,
            previous_status,
            new_status,
            previous_taxon_node_id,
            new_taxon_node_id,
            previous_rank,
            new_rank,
            new_score,
            reason,
            created_at
          )
          VALUES (
            $1, $2, $3, 'needs_id', 'needs_id', $4, $4,
            'species', 'species', 0.65, 'identification_withdrawn',
            '2026-07-30T13:10:00.000Z'
          )
        `,
        [crypto.randomUUID(), requestId, postId, taxonId],
      );
      await client.queryArray(
        `
          INSERT INTO public.community_consensus_events (
            id,
            request_id,
            post_id,
            previous_status,
            new_status,
            previous_taxon_node_id,
            new_taxon_node_id,
            previous_rank,
            new_rank,
            new_score,
            reason,
            created_at
          )
          VALUES (
            $1, $2, $3, 'needs_id', 'resolved', $4, $4,
            'species', 'species', 0.9, 'identification_submitted',
            '2026-07-30T13:15:00.000Z'
          )
        `,
        [crypto.randomUUID(), requestId, postId, taxonId],
      );

      const activityRows = await client.queryObject<ActivityRow>(
        `
          SELECT
            activity_id,
            activity_type,
            activity_at,
            suggestion_count,
            recent_actor_names,
            consensus_score,
            request_group
          FROM public.get_community_identification_activity(
            $1,
            30,
            NULL,
            NULL,
            'all',
            'all'
          )
          WHERE request_id = $2
        `,
        [viewerId, requestId],
      );

      assertEquals(
        activityRows.rows.map((row) => row.activity_type),
        [
          "resolved",
          "consensus_changed",
          "suggestion_burst",
          "suggestion_burst",
        ],
      );
      const groupedBurst = activityRows.rows.find((row) =>
        row.suggestion_count === 5
      );
      assert(groupedBurst != null, "Missing grouped suggestion burst.");
      assertEquals(
        groupedBurst.recent_actor_names,
        ["Actor B", "Actor C", "Actor D"],
      );
      assertEquals(groupedBurst.request_group, "plants");
      assertEquals(Number(groupedBurst.consensus_score), 0.44);
      const latestBurst = activityRows.rows.find((row) =>
        row.suggestion_count === 1
      );
      assertEquals(Number(latestBurst?.consensus_score), 0.55);

      const ownerScopeRows = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id
          FROM public.get_community_identification_activity(
            $1, 30, NULL, NULL, 'mine', 'plants'
          )
          WHERE request_id = $2
        `,
        [ownerId, requestId],
      );
      const viewerScopeRows = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id
          FROM public.get_community_identification_activity(
            $1, 30, NULL, NULL, 'mine', 'plants'
          )
          WHERE request_id = $2
        `,
        [viewerId, requestId],
      );
      const wrongGroupRows = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id
          FROM public.get_community_identification_activity(
            $1, 30, NULL, NULL, 'all', 'birds'
          )
          WHERE request_id = $2
        `,
        [viewerId, requestId],
      );
      assertEquals(ownerScopeRows.rows.length, 4);
      assertEquals(viewerScopeRows.rows.length, 0);
      assertEquals(wrongGroupRows.rows.length, 0);

      const tieLowId = "00000000-0000-4000-8000-000000000101";
      const tieHighId = "00000000-0000-4000-8000-000000000102";
      await client.queryArray(
        `
          INSERT INTO internal.community_identification_activity_groups (
            id,
            request_id,
            post_id,
            request_generation_at,
            activity_type,
            burst_started_at,
            activity_at,
            latest_taxon_node_id
          )
          VALUES
            ($1, $3, $4, $5, 'suggestion_burst', $6, $6, $7),
            ($2, $3, $4, $5, 'suggestion_burst', $6, $6, $7)
        `,
        [
          tieLowId,
          tieHighId,
          requestId,
          postId,
          generationAt,
          "2026-07-30T14:00:00.000Z",
          taxonId,
        ],
      );
      await client.queryArray(
        `
          INSERT INTO internal.community_identification_activity_actors (
            activity_group_id,
            user_id,
            suggestion_count,
            last_suggested_at
          )
          VALUES
            ($1, $3, 1, $4),
            ($2, $3, 1, $4)
        `,
        [
          tieLowId,
          tieHighId,
          actorAId,
          "2026-07-30T14:00:00.000Z",
        ],
      );

      const firstPage = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id, activity_type, activity_at
          FROM public.get_community_identification_activity(
            $1, 1, NULL, NULL, 'mine', 'all'
          )
          WHERE request_id = $2
        `,
        [ownerId, requestId],
      );
      const secondPage = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id, activity_type, activity_at
          FROM public.get_community_identification_activity(
            $1, 1, $3, $4, 'mine', 'all'
          )
          WHERE request_id = $2
        `,
        [
          ownerId,
          requestId,
          firstPage.rows[0].activity_at,
          firstPage.rows[0].activity_id,
        ],
      );
      assertEquals(firstPage.rows.length, 1);
      assertEquals(secondPage.rows.length, 1);
      assertEquals(firstPage.rows[0].activity_id, tieHighId);
      assertEquals(secondPage.rows[0].activity_id, tieLowId);
      await client.queryArray(
        `
          DELETE FROM internal.community_identification_activity_groups
          WHERE id IN ($1, $2)
        `,
        [tieLowId, tieHighId],
      );

      await client.queryArray(
        "INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2)",
        [viewerId, ownerId],
      );
      const blockedRows = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id
          FROM public.get_community_identification_activity(
            $1, 30, NULL, NULL, 'all', 'all'
          )
          WHERE request_id = $2
        `,
        [viewerId, requestId],
      );
      assertEquals(blockedRows.rows.length, 0);
      await client.queryArray(
        "DELETE FROM public.user_blocks WHERE blocker_id = $1 AND blocked_id = $2",
        [viewerId, ownerId],
      );

      const visibleActivityCount = async (): Promise<number> => {
        const rows = await client.queryObject<{ activity_count: number }>(
          `
            SELECT COUNT(*)::INTEGER AS activity_count
            FROM public.get_community_identification_activity(
              $1, 30, NULL, NULL, 'all', 'all'
            )
            WHERE request_id = $2
          `,
          [viewerId, requestId],
        );
        return rows.rows[0].activity_count;
      };

      await client.queryArray(
        "UPDATE public.users SET is_shadowbanned = TRUE WHERE id = $1",
        [ownerId],
      );
      assertEquals(await visibleActivityCount(), 0);
      await client.queryArray(
        "UPDATE public.users SET is_shadowbanned = FALSE WHERE id = $1",
        [ownerId],
      );

      await client.queryArray(
        "UPDATE public.scans SET is_tombstoned = TRUE WHERE id = $1",
        [scanId],
      );
      assertEquals(await visibleActivityCount(), 0);
      await client.queryArray(
        "UPDATE public.scans SET is_tombstoned = FALSE WHERE id = $1",
        [scanId],
      );

      await client.queryArray(
        "UPDATE public.explore_posts SET unshared_at = NOW() WHERE id = $1",
        [postId],
      );
      assertEquals(await visibleActivityCount(), 0);
      await client.queryArray(
        "UPDATE public.explore_posts SET unshared_at = NULL WHERE id = $1",
        [postId],
      );

      await client.queryArray(
        `
          UPDATE public.explore_posts
          SET media_health_status = 'quarantined'
          WHERE id = $1
        `,
        [postId],
      );
      assertEquals(await visibleActivityCount(), 0);
      await client.queryArray(
        `
          UPDATE public.explore_posts
          SET media_health_status = 'healthy'
          WHERE id = $1
        `,
        [postId],
      );

      await client.queryArray(
        `
          UPDATE public.explore_post_media
          SET health_status = 'missing'
          WHERE post_id = $1
        `,
        [postId],
      );
      assertEquals(await visibleActivityCount(), 0);
      await client.queryArray(
        `
          UPDATE public.explore_post_media
          SET health_status = 'healthy'
          WHERE post_id = $1
        `,
        [postId],
      );

      const reopenedAt = "2026-07-31T10:00:00.000Z";
      await client.queryArray(
        `
          UPDATE public.explore_community_requests
          SET requested_at = $2,
              updated_at = $2
          WHERE id = $1
        `,
        [requestId, reopenedAt],
      );
      await insertSuggestion(viewerId, "2026-07-31T10:05:00.000Z");

      const generationRows = await client.queryObject<ProjectionRow>(
        `
          SELECT
            activity_group.activity_type,
            activity_group.request_generation_at,
            COALESCE(SUM(activity_actor.suggestion_count), 0)::INTEGER
              AS suggestion_count
          FROM internal.community_identification_activity_groups
            AS activity_group
          LEFT JOIN internal.community_identification_activity_actors
            AS activity_actor
            ON activity_actor.activity_group_id = activity_group.id
          WHERE activity_group.request_id = $1
          GROUP BY
            activity_group.id,
            activity_group.activity_type,
            activity_group.request_generation_at
        `,
        [requestId],
      );
      assertEquals(generationRows.rows.length, 5);
      assertEquals(
        generationRows.rows.filter((row) =>
          row.request_generation_at.toISOString() === reopenedAt
        ).length,
        1,
      );

      const reopenedFeedRows = await client.queryObject<ActivityRow>(
        `
          SELECT activity_id, activity_type, activity_at
          FROM public.get_community_identification_activity(
            $1, 30, NULL, NULL, 'all', 'all'
          )
          WHERE request_id = $2
        `,
        [viewerId, requestId],
      );
      assertEquals(reopenedFeedRows.rows.length, 1);
      assertEquals(reopenedFeedRows.rows[0].activity_type, "suggestion_burst");
    },
  );
});
