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
      assertEquals(row.location_sharing, "open");
    },
  );
});
