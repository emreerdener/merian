import { assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ExploreHashtagPostRow = {
  post_id: string;
};

Deno.test("Explore hashtag posts DB - returns visible tagged posts with cursor pagination", async () => {
  await withExploreDbTest(
    "exploreHashtagPostsDb.test",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const visiblePostIds = [
        "00000000-0000-0000-0000-000000000311",
        "00000000-0000-0000-0000-000000000322",
      ];

      await insertUser(client, viewerId, "Tag Viewer");
      await insertUser(client, authorId, "Tag Author");
      await insertSpecies(client, speciesId, "Rosa hashtagia");

      for (let index = 0; index < visiblePostIds.length; index += 1) {
        const scanId = crypto.randomUUID();
        await insertScan(client, {
          id: scanId,
          userId: authorId,
          speciesId,
          latitude: 30.2672 + index,
          longitude: -97.7431 - index,
          geoprivacy: "open",
        });
        await insertExplorePost(client, {
          id: visiblePostIds[index],
          userId: authorId,
          scanId,
          sharedAt: index === 0
            ? "2026-05-12T12:00:00.000Z"
            : "2026-05-11T12:00:00.000Z",
        });
      }

      const mediaEmptyScanId = crypto.randomUUID();
      const mediaEmptyPostId = crypto.randomUUID();
      await insertScan(client, {
        id: mediaEmptyScanId,
        userId: authorId,
        speciesId,
        latitude: 30.2,
        longitude: -97.2,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: mediaEmptyPostId,
        userId: authorId,
        scanId: mediaEmptyScanId,
        sharedAt: "2026-05-13T12:00:00.000Z",
        refreshMedia: false,
      });

      const untaggedScanId = crypto.randomUUID();
      const untaggedPostId = crypto.randomUUID();
      await insertScan(client, {
        id: untaggedScanId,
        userId: authorId,
        speciesId,
        latitude: 30.3,
        longitude: -97.3,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: untaggedPostId,
        userId: authorId,
        scanId: untaggedScanId,
        sharedAt: "2026-05-14T12:00:00.000Z",
      });

      await client.queryArray(
        `
          INSERT INTO public.explore_post_hashtags (post_id, tag)
          VALUES ($1, 'citybioblitz'), ($2, 'citybioblitz'), ($3, 'citybioblitz')
        `,
        [visiblePostIds[0], visiblePostIds[1], mediaEmptyPostId],
      );

      const firstPage = await client.queryObject<ExploreHashtagPostRow>(
        `
          SELECT post_id
          FROM public.get_explore_hashtag_posts($1, 'citybioblitz', 1, NULL, NULL)
        `,
        [viewerId],
      );
      assertEquals(firstPage.rows.map((row) => row.post_id), [
        visiblePostIds[0],
      ]);

      const secondPage = await client.queryObject<ExploreHashtagPostRow>(
        `
          SELECT post_id
          FROM public.get_explore_hashtag_posts($1, 'citybioblitz', 10, $2::timestamptz, $3::uuid)
        `,
        [viewerId, "2026-05-12T12:00:00.000Z", visiblePostIds[0]],
      );
      assertEquals(secondPage.rows.map((row) => row.post_id), [
        visiblePostIds[1],
      ]);
    },
  );
});
