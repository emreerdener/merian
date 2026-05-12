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

type TrendingExploreFeedRow = ExploreFeedRow & {
  ranking_value: number;
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

Deno.test("Explore feed DB - blocked, unshared, and media-cleared posts are excluded from the feed", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const visibleOwnerId = crypto.randomUUID();
    const blockedOwnerId = crypto.randomUUID();
    const mediaClearedOwnerId = crypto.randomUUID();
    const unsharedOwnerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, viewerId, "Feed Viewer");
    await insertUser(client, visibleOwnerId, "Visible Owner");
    await insertUser(client, blockedOwnerId, "Blocked Owner");
    await insertUser(client, mediaClearedOwnerId, "Media Cleared Owner");
    await insertUser(client, unsharedOwnerId, "Unshared Owner");
    await insertSpecies(client, speciesId, "Rosa visibilis");

    const visibleScanId = crypto.randomUUID();
    const blockedScanId = crypto.randomUUID();
    const mediaClearedScanId = crypto.randomUUID();
    const unsharedScanId = crypto.randomUUID();
    const visiblePostId = crypto.randomUUID();
    const blockedPostId = crypto.randomUUID();
    const mediaClearedPostId = crypto.randomUUID();
    const unsharedPostId = crypto.randomUUID();

    await insertScan(client, {
      id: visibleScanId,
      userId: visibleOwnerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: blockedScanId,
      userId: blockedOwnerId,
      speciesId,
      latitude: 30.2772,
      longitude: -97.7531,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: mediaClearedScanId,
      userId: mediaClearedOwnerId,
      speciesId,
      latitude: 30.2872,
      longitude: -97.7631,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: unsharedScanId,
      userId: unsharedOwnerId,
      speciesId,
      latitude: 30.2972,
      longitude: -97.7731,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: visiblePostId,
      userId: visibleOwnerId,
      scanId: visibleScanId,
      sharedAt: "2026-04-28T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: blockedPostId,
      userId: blockedOwnerId,
      scanId: blockedScanId,
      sharedAt: "2026-04-28T12:05:00.000Z",
    });
    await insertExplorePost(client, {
      id: mediaClearedPostId,
      userId: mediaClearedOwnerId,
      scanId: mediaClearedScanId,
      sharedAt: "2026-04-28T12:10:00.000Z",
    });
    await insertExplorePost(client, {
      id: unsharedPostId,
      userId: unsharedOwnerId,
      scanId: unsharedScanId,
      sharedAt: "2026-04-28T12:15:00.000Z",
    });

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [viewerId, blockedOwnerId],
    );

    await client.queryArray(
      `
        UPDATE public.scans
        SET image_storage_urls = '{}'::text[]
        WHERE id = $1
      `,
      [mediaClearedScanId],
    );

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET unshared_at = NOW()
        WHERE id = $1
      `,
      [unsharedPostId],
    );

    const rows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(rows.rows.map((row) => row.post_id), [visiblePostId]);
  });
});

Deno.test("Explore following feed DB - returns only followed authors' visible posts", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const followedOwnerId = crypto.randomUUID();
    const unfollowedOwnerId = crypto.randomUUID();
    const blockedOwnerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, viewerId, "Following Viewer");
    await insertUser(client, followedOwnerId, "Followed Owner");
    await insertUser(client, unfollowedOwnerId, "Unfollowed Owner");
    await insertUser(client, blockedOwnerId, "Blocked Followed Owner");
    await insertSpecies(client, speciesId, "Rosa sequitur");

    const followedPostId = crypto.randomUUID();
    const unfollowedPostId = crypto.randomUUID();
    const blockedPostId = crypto.randomUUID();
    const followedScanId = crypto.randomUUID();
    const unfollowedScanId = crypto.randomUUID();
    const blockedScanId = crypto.randomUUID();

    await insertScan(client, {
      id: followedScanId,
      userId: followedOwnerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: unfollowedScanId,
      userId: unfollowedOwnerId,
      speciesId,
      latitude: 30.2772,
      longitude: -97.7531,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: blockedScanId,
      userId: blockedOwnerId,
      speciesId,
      latitude: 30.2872,
      longitude: -97.7631,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: followedPostId,
      userId: followedOwnerId,
      scanId: followedScanId,
      sharedAt: "2026-05-10T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: unfollowedPostId,
      userId: unfollowedOwnerId,
      scanId: unfollowedScanId,
      sharedAt: "2026-05-10T12:05:00.000Z",
    });
    await insertExplorePost(client, {
      id: blockedPostId,
      userId: blockedOwnerId,
      scanId: blockedScanId,
      sharedAt: "2026-05-10T12:10:00.000Z",
    });

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2), ($1, $3)
      `,
      [viewerId, followedOwnerId, blockedOwnerId],
    );

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [viewerId, blockedOwnerId],
    );

    const rows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed_following($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(rows.rows.map((row) => row.post_id), [followedPostId]);
  });
});

Deno.test("Explore trending feed DB - ranking pagination preserves stable ordering across score ties", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, ownerId, "Trending Owner");
    await insertUser(client, viewerId, "Trending Viewer");
    await insertSpecies(client, speciesId, "Rosa trendingis");

    const posts = [
      {
        postId: "00000000-0000-0000-0000-000000000110",
        scanId: crypto.randomUUID(),
        sharedAt: "2026-04-28T12:00:00.000Z",
        likeCount: 2,
      },
      {
        postId: "00000000-0000-0000-0000-000000000120",
        scanId: crypto.randomUUID(),
        sharedAt: "2026-04-28T12:05:00.000Z",
        likeCount: 3,
      },
      {
        postId: "00000000-0000-0000-0000-000000000130",
        scanId: crypto.randomUUID(),
        sharedAt: "2026-04-28T12:03:00.000Z",
        likeCount: 2,
      },
      {
        postId: "00000000-0000-0000-0000-000000000140",
        scanId: crypto.randomUUID(),
        sharedAt: "2026-04-28T11:30:00.000Z",
        likeCount: 1,
      },
    ];

    for (let index = 0; index < posts.length; index += 1) {
      await insertScan(client, {
        id: posts[index].scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672 + (index * 0.01),
        longitude: -97.7431 - (index * 0.01),
        geoprivacy: "open",
      });

      await insertExplorePost(client, {
        id: posts[index].postId,
        userId: ownerId,
        scanId: posts[index].scanId,
        sharedAt: posts[index].sharedAt,
      });

      for (let likeIndex = 0; likeIndex < posts[index].likeCount; likeIndex += 1) {
        const likerId = crypto.randomUUID();
        await insertUser(client, likerId, `Trending Liker ${index}-${likeIndex}`);
        await client.queryArray(
          `
            INSERT INTO public.explore_post_likes (post_id, user_id, created_at)
            VALUES ($1, $2, NOW() - INTERVAL '1 day')
          `,
          [posts[index].postId, likerId],
        );
      }
    }

    const firstPage = await client.queryObject<TrendingExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at, ranking_value
        FROM public.get_explore_feed_trending($1, 2, NULL, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(
      firstPage.rows.map((row) => row.post_id),
      [
        "00000000-0000-0000-0000-000000000120",
        "00000000-0000-0000-0000-000000000130",
      ],
    );
    assertEquals(firstPage.rows.map((row) => row.ranking_value), [3, 2]);

    const cursor = firstPage.rows[1];
    const secondPage = await client.queryObject<TrendingExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at, ranking_value
        FROM public.get_explore_feed_trending($1, 2, $2::integer, $3::timestamptz, $4::uuid)
      `,
      [viewerId, cursor.ranking_value, cursor.shared_at, cursor.post_id],
    );

    assertEquals(
      secondPage.rows.map((row) => row.post_id),
      [
        "00000000-0000-0000-0000-000000000110",
        "00000000-0000-0000-0000-000000000140",
      ],
    );

    const combinedIds = [
      ...firstPage.rows.map((row) => row.post_id),
      ...secondPage.rows.map((row) => row.post_id),
    ];
    assertEquals(new Set(combinedIds).size, 4);
  });
});

Deno.test("Explore nearby feed DB - filters to the nearby radius and keeps recent ordering", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, ownerId, "Nearby Owner");
    await insertUser(client, viewerId, "Nearby Viewer");
    await insertSpecies(client, speciesId, "Rosa nearbyis");

    const nearbyOlderScanId = crypto.randomUUID();
    const nearbyNewerScanId = crypto.randomUUID();
    const farScanId = crypto.randomUUID();
    const nearbyOlderPostId = crypto.randomUUID();
    const nearbyNewerPostId = crypto.randomUUID();
    const farPostId = crypto.randomUUID();

    await insertScan(client, {
      id: nearbyOlderScanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2700,
      longitude: -97.7500,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: nearbyNewerScanId,
      userId: ownerId,
      speciesId,
      latitude: 30.3100,
      longitude: -97.7000,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: farScanId,
      userId: ownerId,
      speciesId,
      latitude: 32.7767,
      longitude: -96.7970,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: nearbyOlderPostId,
      userId: ownerId,
      scanId: nearbyOlderScanId,
      sharedAt: "2026-04-28T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: nearbyNewerPostId,
      userId: ownerId,
      scanId: nearbyNewerScanId,
      sharedAt: "2026-04-28T12:10:00.000Z",
    });
    await insertExplorePost(client, {
      id: farPostId,
      userId: ownerId,
      scanId: farScanId,
      sharedAt: "2026-04-28T12:20:00.000Z",
    });

    const rows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed_nearby($1, 30.2672, -97.7431, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(
      rows.rows.map((row) => row.post_id),
      [nearbyNewerPostId, nearbyOlderPostId],
    );
  });
});
