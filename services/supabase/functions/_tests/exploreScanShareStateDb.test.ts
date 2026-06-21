import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ExploreScanShareStateRow = {
  scan_id: string;
  post_id: string | null;
  shared_at: string | null;
  community_request_id: string | null;
  community_request_status: "needs_id" | "resolved" | "withdrawn" | null;
  is_explore_feed_visible: boolean;
  location_sharing: "open" | "obscured" | "private";
};

Deno.test("Explore scan share state DB - returns active Explore post for an owned shared scan", async () => {
  await withExploreDbTest(
    "exploreScanShareStateDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();

      await insertUser(client, ownerId, "Share State Owner");
      await insertSpecies(client, speciesId, "Rosa share-state");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
      });

      const result = await client.queryObject<ExploreScanShareStateRow>(
        `
        SELECT
          scan_id,
          post_id,
          shared_at::text AS shared_at,
          community_request_id,
          community_request_status,
          is_explore_feed_visible,
          location_sharing
        FROM public.get_scan_explore_share_state($1, $2)
      `,
        [ownerId, scanId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.scan_id, scanId);
      assertEquals(row.post_id, postId);
      assertExists(row.shared_at);
      assertEquals(row.community_request_id, null);
      assertEquals(row.community_request_status, null);
      assertEquals(row.is_explore_feed_visible, true);
      assertEquals(row.location_sharing, "open");
    },
  );
});

Deno.test("Explore scan share state DB - keeps the shared post when scan geoprivacy becomes private", async () => {
  await withExploreDbTest(
    "exploreScanShareStateDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();

      await insertUser(client, ownerId, "Share State Private");
      await insertSpecies(client, speciesId, "Quercus share-state");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 41.8781,
        longitude: -87.6298,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
        locationSharing: "open",
      });

      await client.queryArray(
        `
        UPDATE public.scans
        SET geoprivacy = 'private'
        WHERE id = $1
      `,
        [scanId],
      );

      const result = await client.queryObject<ExploreScanShareStateRow>(
        `
        SELECT
          scan_id,
          post_id,
          shared_at::text AS shared_at,
          community_request_id,
          community_request_status,
          is_explore_feed_visible,
          location_sharing
        FROM public.get_scan_explore_share_state($1, $2)
      `,
        [ownerId, scanId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.scan_id, scanId);
      assertEquals(row.post_id, postId);
      assertExists(row.shared_at);
      assertEquals(row.community_request_id, null);
      assertEquals(row.community_request_status, null);
      assertEquals(row.is_explore_feed_visible, true);
      assertEquals(row.location_sharing, "open");
    },
  );
});

Deno.test("Explore scan share state DB - restores pending community request state without feed visibility", async () => {
  await withExploreDbTest(
    "exploreScanShareStateDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const requestId = crypto.randomUUID();

      await insertUser(client, ownerId, "Share State Pending");
      await insertSpecies(client, speciesId, "Rosa pending-share-state");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 35.2271,
        longitude: -80.8431,
        geoprivacy: "obscured",
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
        locationSharing: "obscured",
      });
      await client.queryArray(
        `
        INSERT INTO public.explore_community_requests (
          id,
          post_id,
          scan_id,
          requested_by
        )
        VALUES ($1, $2, $3, $4)
      `,
        [requestId, postId, scanId, ownerId],
      );

      const result = await client.queryObject<ExploreScanShareStateRow>(
        `
        SELECT
          scan_id,
          post_id,
          shared_at::text AS shared_at,
          community_request_id,
          community_request_status,
          is_explore_feed_visible,
          location_sharing
        FROM public.get_scan_explore_share_state($1, $2)
      `,
        [ownerId, scanId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.scan_id, scanId);
      assertEquals(row.post_id, postId);
      assertExists(row.shared_at);
      assertEquals(row.community_request_id, requestId);
      assertEquals(row.community_request_status, "needs_id");
      assertEquals(row.is_explore_feed_visible, false);
      assertEquals(row.location_sharing, "obscured");
    },
  );
});

Deno.test("Explore scan share state DB - hides resolved community requests until explicit Explore publish", async () => {
  await withExploreDbTest(
    "exploreScanShareStateDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const requestId = crypto.randomUUID();
      const taxonId = crypto.randomUUID();
      const pathKey = `test${crypto.randomUUID().replaceAll("-", "")}`;

      await insertUser(client, ownerId, "Share State Resolved");
      await insertSpecies(client, speciesId, "Rosa resolved-share-state");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 47.6062,
        longitude: -122.3321,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
      });
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
          'Rosa resolved-share-state',
          'Resolved Rose',
          $3
        )
      `,
        [taxonId, pathKey, speciesId],
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
          resolved_at
        )
        VALUES ($1, $2, $3, $4, 'resolved', $5, $5, now())
      `,
        [requestId, postId, scanId, ownerId, taxonId],
      );
      await client.queryArray(
        `
        UPDATE public.explore_observation_projection
        SET projection_state = 'community_resolved',
            community_request_id = $1,
            public_taxon_node_id = $2
        WHERE post_id = $3
      `,
        [requestId, taxonId, postId],
      );

      const beforePublish = await client.queryObject<ExploreScanShareStateRow>(
        `
        SELECT
          scan_id,
          post_id,
          shared_at::text AS shared_at,
          community_request_id,
          community_request_status,
          is_explore_feed_visible,
          location_sharing
        FROM public.get_scan_explore_share_state($1, $2)
      `,
        [ownerId, scanId],
      );
      const beforeFeedRows = await client.queryObject<{ post_id: string }>(
        `
        SELECT post_id
        FROM public.explore_projected_post_cards($1)
        WHERE post_id = $2
      `,
        [ownerId, postId],
      );

      assertEquals(beforePublish.rows[0].community_request_id, requestId);
      assertEquals(beforePublish.rows[0].community_request_status, "resolved");
      assertEquals(beforePublish.rows[0].is_explore_feed_visible, false);
      assertEquals(beforeFeedRows.rows.length, 0);

      await client.queryArray(
        `
        UPDATE public.explore_community_requests
        SET explore_published_at = now()
        WHERE id = $1
      `,
        [requestId],
      );

      const afterPublish = await client.queryObject<ExploreScanShareStateRow>(
        `
        SELECT
          scan_id,
          post_id,
          shared_at::text AS shared_at,
          community_request_id,
          community_request_status,
          is_explore_feed_visible,
          location_sharing
        FROM public.get_scan_explore_share_state($1, $2)
      `,
        [ownerId, scanId],
      );
      const afterFeedRows = await client.queryObject<{ post_id: string }>(
        `
        SELECT post_id
        FROM public.explore_projected_post_cards($1)
        WHERE post_id = $2
      `,
        [ownerId, postId],
      );

      assertEquals(afterPublish.rows[0].post_id, postId);
      assertEquals(afterPublish.rows[0].community_request_id, requestId);
      assertEquals(afterPublish.rows[0].community_request_status, "resolved");
      assertEquals(afterPublish.rows[0].is_explore_feed_visible, true);
      assertEquals(afterFeedRows.rows.map((row) => row.post_id), [postId]);
    },
  );
});
