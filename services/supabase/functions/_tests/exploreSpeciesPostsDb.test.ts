import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type SpeciesPostRow = {
  post_id: string;
  image_quality_score: number | null;
  reference_thumbnail_url: string | null;
};

type SpeciesPostFixture = Parameters<typeof insertExplorePost>[1];

async function insertSpeciesPost(
  client: Client,
  options: SpeciesPostFixture,
): Promise<void> {
  await insertExplorePost(client, options);
}

async function fetchSpeciesPosts(
  client: Client,
  viewerId: string,
  speciesId: string,
  limit = 30,
  beforeImageQualityScore: number | null = null,
  beforeSharedAt: string | null = null,
  beforePostId: string | null = null,
): Promise<SpeciesPostRow[]> {
  const result = await client.queryObject<SpeciesPostRow>(
    `
      SELECT post_id, image_quality_score, reference_thumbnail_url
      FROM public.get_explore_species_posts(
        $1::uuid,
        $2::uuid,
        $3::integer,
        $4::smallint,
        $5::timestamptz,
        $6::uuid
      )
    `,
    [
      viewerId,
      speciesId,
      limit,
      beforeImageQualityScore,
      beforeSharedAt,
      beforePostId,
    ],
  );
  return result.rows;
}

Deno.test("Explore species posts DB - ranks quality first and paginates through the unscored tier", async () => {
  await withExploreDbTest(
    "exploreSpeciesPostsDb.quality",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      await insertUser(client, viewerId, "Species Viewer");
      await insertUser(client, authorId, "Species Author");
      await insertSpecies(client, speciesId, "Rosa qualitatis");
      await client.queryArray(
        "UPDATE public.species_dictionary SET reference_image_url = $2 WHERE id = $1",
        [speciesId, "https://media.merian.app/reference.webp"],
      );

      const fixtures = [
        {
          postId: "00000000-0000-4000-8000-000000000095",
          score: 95,
          sharedAt: "2026-07-10T12:00:00.000Z",
        },
        {
          postId: "00000000-0000-4000-8000-000000000082",
          score: 80,
          sharedAt: "2026-07-12T12:00:00.000Z",
        },
        {
          postId: "00000000-0000-4000-8000-000000000081",
          score: 80,
          sharedAt: "2026-07-12T12:00:00.000Z",
        },
        {
          postId: "00000000-0000-4000-8000-000000000010",
          score: 0,
          sharedAt: "2026-07-15T12:00:00.000Z",
        },
        {
          postId: "00000000-0000-4000-8000-000000000002",
          score: null,
          sharedAt: "2026-07-14T12:00:00.000Z",
        },
        {
          postId: "00000000-0000-4000-8000-000000000001",
          score: null,
          sharedAt: "2026-07-13T12:00:00.000Z",
        },
      ];

      for (const fixture of fixtures) {
        const scanId = crypto.randomUUID();
        await insertScan(client, {
          id: scanId,
          userId: authorId,
          speciesId,
          latitude: 30.2,
          longitude: -97.7,
          geoprivacy: "open",
          imageQualityScore: fixture.score,
        });
        await insertSpeciesPost(client, {
          id: fixture.postId,
          userId: authorId,
          scanId,
          sharedAt: fixture.sharedAt,
        });
      }

      const allRows = await fetchSpeciesPosts(
        client,
        viewerId,
        speciesId,
      );
      assertEquals(
        allRows.map((row) => row.post_id),
        fixtures.map((row) => row.postId),
      );
      assertEquals(
        allRows.map((row) => row.image_quality_score),
        [95, 80, 80, 0, null, null],
      );
      assertEquals(
        allRows[0].reference_thumbnail_url,
        "https://media.merian.app/reference.webp",
      );

      const afterScored = await fetchSpeciesPosts(
        client,
        viewerId,
        speciesId,
        30,
        80,
        "2026-07-12T12:00:00.000Z",
        fixtures[2].postId,
      );
      assertEquals(afterScored.map((row) => row.post_id), [
        fixtures[3].postId,
        fixtures[4].postId,
        fixtures[5].postId,
      ]);

      const afterZero = await fetchSpeciesPosts(
        client,
        viewerId,
        speciesId,
        30,
        0,
        "2026-07-15T12:00:00.000Z",
        fixtures[3].postId,
      );
      assertEquals(afterZero.map((row) => row.post_id), [
        fixtures[4].postId,
        fixtures[5].postId,
      ]);

      const afterHigherTie = await fetchSpeciesPosts(
        client,
        viewerId,
        speciesId,
        30,
        80,
        "2026-07-12T12:00:00.000Z",
        fixtures[1].postId,
      );
      assertEquals(afterHigherTie.map((row) => row.post_id), [
        fixtures[2].postId,
        fixtures[3].postId,
        fixtures[4].postId,
        fixtures[5].postId,
      ]);

      const afterUnscored = await fetchSpeciesPosts(
        client,
        viewerId,
        speciesId,
        30,
        null,
        "2026-07-14T12:00:00.000Z",
        fixtures[4].postId,
      );
      assertEquals(afterUnscored.map((row) => row.post_id), [
        fixtures[5].postId,
      ]);
    },
  );
});

Deno.test("Explore species posts DB - uses confirmed and community-resolved species IDs", async () => {
  await withExploreDbTest(
    "exploreSpeciesPostsDb.effectiveSpecies",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const originalSpeciesId = crypto.randomUUID();
      const confirmedSpeciesId = crypto.randomUUID();
      const communitySpeciesId = crypto.randomUUID();
      await insertUser(client, viewerId, "Effective Viewer");
      await insertUser(client, authorId, "Effective Author");
      await insertSpecies(client, originalSpeciesId, "Rosa originalis");
      await insertSpecies(client, confirmedSpeciesId, "Rosa confirmata");
      await insertSpecies(client, communitySpeciesId, "Rosa communitas");

      const confirmedScanId = crypto.randomUUID();
      const confirmedPostId = crypto.randomUUID();
      await insertScan(client, {
        id: confirmedScanId,
        userId: authorId,
        speciesId: originalSpeciesId,
        confirmedSpeciesId,
        latitude: 30.2,
        longitude: -97.7,
        geoprivacy: "open",
        imageQualityScore: 90,
      });
      await insertSpeciesPost(client, {
        id: confirmedPostId,
        userId: authorId,
        scanId: confirmedScanId,
      });

      const communityScanId = crypto.randomUUID();
      const communityPostId = crypto.randomUUID();
      const communityRequestId = crypto.randomUUID();
      await insertScan(client, {
        id: communityScanId,
        userId: authorId,
        speciesId: originalSpeciesId,
        latitude: 30.3,
        longitude: -97.8,
        geoprivacy: "open",
        imageQualityScore: 85,
      });
      await insertSpeciesPost(client, {
        id: communityPostId,
        userId: authorId,
        scanId: communityScanId,
      });

      const taxonNodeId = crypto.randomUUID();
      await client.queryArray(
        `
          INSERT INTO public.taxon_nodes (
            id,
            taxonomy_version_id,
            path,
            rank,
            scientific_name,
            common_name,
            species_id
          )
          VALUES (
            $1,
            public.active_taxonomy_version_id(),
            $2::ltree,
            'species',
            'Rosa communitas',
            'Community Rose',
            $3
          )
        `,
        [
          taxonNodeId,
          `species_${communitySpeciesId.replaceAll("-", "_")}`,
          communitySpeciesId,
        ],
      );
      await client.queryArray(
        `
          INSERT INTO public.explore_community_requests (
            id,
            post_id,
            scan_id,
            requested_by,
            status,
            resolved_taxon_node_id,
            resolved_observation_taxon_node_id,
            resolved_at,
            explore_published_at
          )
          VALUES ($1, $2, $3, $4, 'resolved', $5, $5, now(), now())
        `,
        [
          communityRequestId,
          communityPostId,
          communityScanId,
          authorId,
          taxonNodeId,
        ],
      );
      await client.queryArray(
        `
          INSERT INTO public.explore_observation_projection (
            post_id,
            scan_id,
            projection_state,
            community_request_id,
            public_taxon_node_id,
            resolved_taxon_node_id
          )
          VALUES ($1, $2, 'community_resolved', $3, $4, $4)
          ON CONFLICT (post_id) DO UPDATE
          SET projection_state = EXCLUDED.projection_state,
              community_request_id = EXCLUDED.community_request_id,
              public_taxon_node_id = EXCLUDED.public_taxon_node_id,
              resolved_taxon_node_id = EXCLUDED.resolved_taxon_node_id
        `,
        [
          communityPostId,
          communityScanId,
          communityRequestId,
          taxonNodeId,
        ],
      );

      const confirmedRows = await fetchSpeciesPosts(
        client,
        viewerId,
        confirmedSpeciesId,
      );
      assertEquals(confirmedRows.map((row) => row.post_id), [confirmedPostId]);

      const communityRows = await fetchSpeciesPosts(
        client,
        viewerId,
        communitySpeciesId,
      );
      assertEquals(communityRows.map((row) => row.post_id), [communityPostId]);

      const originalRows = await fetchSpeciesPosts(
        client,
        viewerId,
        originalSpeciesId,
      );
      assertEquals(originalRows, []);
    },
  );
});

Deno.test("Explore species posts DB - preserves projection visibility and RPC privileges", async () => {
  await withExploreDbTest(
    "exploreSpeciesPostsDb.visibility",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const visibleAuthorId = crypto.randomUUID();
      const blockedAuthorId = crypto.randomUUID();
      const shadowbannedAuthorId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      await insertUser(client, viewerId, "Visibility Viewer");
      await insertUser(client, visibleAuthorId, "Visible Author");
      await insertUser(client, blockedAuthorId, "Blocked Author");
      await insertUser(client, shadowbannedAuthorId, "Shadowbanned Author");
      await client.queryArray(
        "UPDATE public.users SET is_shadowbanned = TRUE WHERE id = $1",
        [shadowbannedAuthorId],
      );
      await insertSpecies(client, speciesId, "Rosa visibilis");

      async function makePost(
        authorId: string,
        postId: string,
      ): Promise<{ scanId: string; postId: string }> {
        const scanId = crypto.randomUUID();
        await insertScan(client, {
          id: scanId,
          userId: authorId,
          speciesId,
          latitude: 30.2,
          longitude: -97.7,
          geoprivacy: "open",
          imageQualityScore: 80,
        });
        await insertSpeciesPost(client, {
          id: postId,
          userId: authorId,
          scanId,
        });
        return { scanId, postId };
      }

      const visible = await makePost(visibleAuthorId, crypto.randomUUID());
      await makePost(blockedAuthorId, crypto.randomUUID());
      await makePost(shadowbannedAuthorId, crypto.randomUUID());
      const tombstoned = await makePost(visibleAuthorId, crypto.randomUUID());
      const unshared = await makePost(visibleAuthorId, crypto.randomUUID());
      const mediaLess = await makePost(visibleAuthorId, crypto.randomUUID());
      const needsId = await makePost(visibleAuthorId, crypto.randomUUID());

      await client.queryArray(
        "INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2)",
        [viewerId, blockedAuthorId],
      );
      await client.queryArray(
        "UPDATE public.scans SET is_tombstoned = TRUE WHERE id = $1",
        [tombstoned.scanId],
      );
      await client.queryArray(
        "UPDATE public.explore_posts SET unshared_at = NOW() WHERE id = $1",
        [unshared.postId],
      );
      await client.queryArray(
        "DELETE FROM public.explore_post_media WHERE post_id = $1",
        [mediaLess.postId],
      );
      await client.queryArray(
        `
          INSERT INTO public.explore_observation_projection (
            post_id,
            scan_id,
            projection_state
          )
          VALUES ($1, $2, 'community_needs_id')
          ON CONFLICT (post_id) DO UPDATE
          SET projection_state = EXCLUDED.projection_state
        `,
        [needsId.postId, needsId.scanId],
      );

      const rows = await fetchSpeciesPosts(client, viewerId, speciesId);
      assertEquals(rows.map((row) => row.post_id), [visible.postId]);

      const privileges = await client.queryObject<{
        public_can_execute: boolean;
        authenticated_can_execute: boolean;
        service_role_can_execute: boolean;
      }>(
        `
          SELECT
            has_function_privilege(
              'public',
              'public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamptz,uuid)',
              'EXECUTE'
            ) AS public_can_execute,
            has_function_privilege(
              'authenticated',
              'public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamptz,uuid)',
              'EXECUTE'
            ) AS authenticated_can_execute,
            has_function_privilege(
              'service_role',
              'public.get_explore_species_posts(uuid,uuid,integer,smallint,timestamptz,uuid)',
              'EXECUTE'
            ) AS service_role_can_execute
        `,
      );
      assertEquals(privileges.rows[0], {
        public_can_execute: false,
        authenticated_can_execute: false,
        service_role_can_execute: true,
      });
    },
  );
});
