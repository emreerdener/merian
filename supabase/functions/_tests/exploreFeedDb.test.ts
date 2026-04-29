import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ExploreFeedRow = {
  post_id: string;
  shared_at: string;
};

Deno.test("Explore feed DB - cursor pagination preserves stable ordering across ties and avoids duplicates", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, ownerId, "Cursor Owner");
    await insertUser(client, viewerId, "Cursor Viewer");
    await insertSpecies(client, speciesId, "Rosa cursoris");

    const postIds = [
      "00000000-0000-0000-0000-000000000010",
      "00000000-0000-0000-0000-000000000020",
      "00000000-0000-0000-0000-000000000030",
      "00000000-0000-0000-0000-000000000040",
    ];

    const scanIds = [
      crypto.randomUUID(),
      crypto.randomUUID(),
      crypto.randomUUID(),
      crypto.randomUUID(),
    ];

    const sharedAtValues = [
      "2026-04-28T12:00:00.000Z",
      "2026-04-28T12:00:00.000Z",
      "2026-04-28T12:05:00.000Z",
      "2026-04-28T11:30:00.000Z",
    ];

    for (let index = 0; index < scanIds.length; index += 1) {
      await insertScan(client, {
        id: scanIds[index],
        userId: ownerId,
        speciesId,
        latitude: 30.2672 + (index * 0.01),
        longitude: -97.7431 - (index * 0.01),
        geoprivacy: "open",
      });

      await insertExplorePost(client, {
        id: postIds[index],
        userId: ownerId,
        scanId: scanIds[index],
        sharedAt: sharedAtValues[index],
      });
    }

    const firstPage = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed($1, 2, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(
      firstPage.rows.map((row) => row.post_id),
      [
        "00000000-0000-0000-0000-000000000030",
        "00000000-0000-0000-0000-000000000020",
      ],
    );

    const cursor = firstPage.rows[1];
    const secondPage = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed($1, 2, $2::timestamptz, $3::uuid)
      `,
      [viewerId, cursor.shared_at, cursor.post_id],
    );

    assertEquals(
      secondPage.rows.map((row) => row.post_id),
      [
        "00000000-0000-0000-0000-000000000010",
        "00000000-0000-0000-0000-000000000040",
      ],
    );

    const combinedIds = [
      ...firstPage.rows.map((row) => row.post_id),
      ...secondPage.rows.map((row) => row.post_id),
    ];
    assertEquals(new Set(combinedIds).size, 4);
  });
});
