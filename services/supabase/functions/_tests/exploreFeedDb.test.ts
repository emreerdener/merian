import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";
import type { PetIdentification } from "../_shared/identify/types.ts";

type ExploreFeedRow = {
  post_id: string;
  shared_at: string;
};

type ExploreLocationRow = {
  public_location_label: string | null;
  location_sharing?: "open" | "obscured" | "private";
};

type ExploreSpeciesNameRow = {
  species_common_name: string;
};

type ExplorePetIdentificationRow = ExploreSpeciesNameRow & {
  species_scientific_name: string;
  pet_identification: PetIdentification | null;
};

type TrendingExploreFeedRow = ExploreFeedRow & {
  ranking_value: number;
};

Deno.test("Explore location sanitizer DB - strips exact addresses and coordinate strings", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const rows = await client.queryObject<{ label: string | null }>(
      `
        SELECT public.sanitize_explore_location(raw_location) AS label
        FROM (
          VALUES
            (1, $1::text),
            (2, $2::text),
            (3, $3::text),
            (4, $4::text),
            (5, $5::text),
            (6, $6::text),
            (7, $7::text),
            (8, $8::text),
            (9, $9::text),
            (10, $10::text),
            (11, $11::text),
            (12, $12::text)
        ) AS cases(sort_order, raw_location)
        ORDER BY sort_order
      `,
      [
        "123 Main St, Austin, TX, United States",
        "Central Park, NY",
        "30.2672, -97.7431",
        "California",
        "Austin, Travis County, TX, United States",
        "Austin",
        "123 Main St, Austin, TX 78701, United States",
        "123 Main St, Austin, Texas 78701, United States",
        "123 Main St, Austin, TX 78701 United States",
        "Little Sarasota Bay",
        "Little Sarasota Bay, FL",
        "FL",
      ],
    );

    assertEquals(
      rows.rows.map((row) => row.label),
      [
        "Austin, TX",
        "New York",
        null,
        "California",
        "Austin, TX",
        "Austin",
        "Austin, TX",
        "Austin, TX",
        "Austin, TX",
        null,
        "Florida",
        "Florida",
      ],
    );
  });
});

Deno.test("Explore feed DB - location labels are city/state only for feed and detail", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Location Owner");
    await insertUser(client, viewerId, "Location Viewer");
    await insertSpecies(client, speciesId, "Rosa locationis");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
      semanticLocation: "123 Main St, Austin, TX, United States",
    });

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      sharedAt: "2026-04-28T12:00:00.000Z",
    });

    const feedRows = await client.queryObject<ExploreLocationRow>(
      `
        SELECT public_location_label
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    const detailRows = await client.queryObject<ExploreLocationRow>(
      `
        SELECT public_location_label
        FROM public.get_explore_post($1, $2)
      `,
      [viewerId, postId],
    );

    assertEquals(feedRows.rows[0]?.public_location_label, "Austin, TX");
    assertEquals(detailRows.rows[0]?.public_location_label, "Austin, TX");
  });
});

Deno.test("Explore feed DB - private post geoprivacy keeps shared post visible without location", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Private Post Owner");
    await insertUser(client, viewerId, "Private Post Viewer");
    await insertSpecies(client, speciesId, "Rosa privaposta");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "private",
      semanticLocation: "Austin, Texas",
    });

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      sharedAt: "2026-04-28T12:05:00.000Z",
      locationSharing: "private",
    });

    const feedRows = await client.queryObject<ExploreLocationRow>(
      `
        SELECT public_location_label, location_sharing
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    const detailRows = await client.queryObject<ExploreLocationRow>(
      `
        SELECT public_location_label, location_sharing
        FROM public.get_explore_post($1, $2)
      `,
      [viewerId, postId],
    );

    assertEquals(feedRows.rows.length, 1);
    assertEquals(feedRows.rows[0]?.public_location_label, null);
    assertEquals(feedRows.rows[0]?.location_sharing, "private");
    assertEquals(detailRows.rows[0]?.public_location_label, null);
    assertEquals(detailRows.rows[0]?.location_sharing, "private");
  });
});

Deno.test("Explore feed DB - post common-name snapshot overrides dictionary name", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Snapshot Owner");
    await insertUser(client, viewerId, "Snapshot Viewer");
    await insertSpecies(client, speciesId, "Odocoileus hemionus");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 38.5816,
      longitude: -121.4944,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      sharedAt: "2026-04-28T12:10:00.000Z",
      speciesCommonName: "Black-Tailed Deer",
    });

    const storedPostRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.explore_posts
        WHERE id = $1
      `,
      [postId],
    );

    assertEquals(
      storedPostRows.rows[0]?.species_common_name,
      "Black-Tailed Deer",
    );

    await client.queryArray(
      `
        UPDATE public.species_dictionary
        SET common_names = '{"en":"Colombian Black-Tailed Deer"}'::jsonb
        WHERE id = $1
      `,
      [speciesId],
    );

    const feedRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    const detailRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.get_explore_post($1, $2)
      `,
      [viewerId, postId],
    );

    assertEquals(feedRows.rows[0]?.species_common_name, "Black-Tailed Deer");
    assertEquals(detailRows.rows[0]?.species_common_name, "Black-Tailed Deer");

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET species_common_name = $1
        WHERE id = $2
      `,
      ["Mule Deer", postId],
    );

    const editedDetailRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.get_explore_post($1, $2)
      `,
      [viewerId, postId],
    );

    assertEquals(editedDetailRows.rows[0]?.species_common_name, "Mule Deer");

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET field_notes = $1
        WHERE id = $2
      `,
      ["Keep the selected name while toggling notes.", postId],
    );

    const preservedRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.explore_posts
        WHERE id = $1
      `,
      [postId],
    );
    const preservedFeedRows = await client.queryObject<ExploreSpeciesNameRow>(
      `
        SELECT species_common_name
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(preservedRows.rows[0]?.species_common_name, "Mule Deer");
    assertEquals(preservedFeedRows.rows[0]?.species_common_name, "Mule Deer");
  });
});

Deno.test("Explore feed DB - exposes pet identification without replacing species names", async () => {
  await withExploreDbTest(
    "exploreFeedDb.petIdentification.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const petIdentification: PetIdentification = {
        species_group: "dog",
        label: "Australian Cattle Dog",
        label_type: "breed",
        confidence_score: 0.91,
        evidence: ["blue roan coat", "compact working-dog build"],
      };

      await insertUser(client, ownerId, "Pet Owner");
      await insertUser(client, viewerId, "Pet Viewer");
      await insertSpecies(client, speciesId, "Canis lupus familiaris");

      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        petIdentification,
      });

      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
        sharedAt: "2026-04-28T12:20:00.000Z",
        speciesCommonName: "Domestic Dog",
      });

      const feedRows = await client.queryObject<ExplorePetIdentificationRow>(
        `
        SELECT species_common_name, species_scientific_name, pet_identification
        FROM public.get_explore_feed($1, 20, NULL, NULL)
        WHERE post_id = $2
      `,
        [viewerId, postId],
      );

      const postRows = await client.queryObject<ExplorePetIdentificationRow>(
        `
        SELECT species_common_name, species_scientific_name, pet_identification
        FROM public.get_explore_post($1, $2)
      `,
        [viewerId, postId],
      );

      assertEquals(feedRows.rows[0]?.species_common_name, "Domestic Dog");
      assertEquals(
        feedRows.rows[0]?.species_scientific_name,
        "Canis lupus familiaris",
      );
      assertEquals(feedRows.rows[0]?.pet_identification, petIdentification);
      assertEquals(postRows.rows[0]?.species_common_name, "Domestic Dog");
      assertEquals(
        postRows.rows[0]?.species_scientific_name,
        "Canis lupus familiaris",
      );
      assertEquals(postRows.rows[0]?.pet_identification, petIdentification);
    },
  );
});

Deno.test("Explore feed DB - canonical public location label repairs landmark-only legacy text", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Canonical Location Owner");
    await insertUser(client, viewerId, "Canonical Location Viewer");
    await insertSpecies(client, speciesId, "Rosa canonica");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 27.3364,
      longitude: -82.5453,
      geoprivacy: "open",
      semanticLocation: "Little Sarasota Bay",
      publicLocationLabel: "Sarasota, FL",
    });

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      sharedAt: "2026-04-28T12:05:00.000Z",
    });

    const rows = await client.queryObject<ExploreLocationRow>(
      `
        SELECT public_location_label
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(rows.rows[0]?.public_location_label, "Sarasota, FL");
  });
});

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

Deno.test("Explore feed DB - blocked, unshared, media-cleared, and moderated posts are excluded while withdrawn requests fall back", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const visibleOwnerId = crypto.randomUUID();
    const withdrawnOwnerId = crypto.randomUUID();
    const blockedOwnerId = crypto.randomUUID();
    const mediaClearedOwnerId = crypto.randomUUID();
    const unsharedOwnerId = crypto.randomUUID();
    const moderatedOwnerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, viewerId, "Feed Viewer");
    await insertUser(client, visibleOwnerId, "Visible Owner");
    await insertUser(client, withdrawnOwnerId, "Withdrawn Owner");
    await insertUser(client, blockedOwnerId, "Blocked Owner");
    await insertUser(client, mediaClearedOwnerId, "Media Cleared Owner");
    await insertUser(client, unsharedOwnerId, "Unshared Owner");
    await insertUser(client, moderatedOwnerId, "Moderated Owner");
    await insertSpecies(client, speciesId, "Rosa visibilis");

    const visibleScanId = crypto.randomUUID();
    const withdrawnScanId = crypto.randomUUID();
    const blockedScanId = crypto.randomUUID();
    const mediaClearedScanId = crypto.randomUUID();
    const unsharedScanId = crypto.randomUUID();
    const moderatedScanId = crypto.randomUUID();
    const visiblePostId = crypto.randomUUID();
    const withdrawnPostId = crypto.randomUUID();
    const blockedPostId = crypto.randomUUID();
    const mediaClearedPostId = crypto.randomUUID();
    const unsharedPostId = crypto.randomUUID();
    const moderatedPostId = crypto.randomUUID();

    await insertScan(client, {
      id: visibleScanId,
      userId: visibleOwnerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: withdrawnScanId,
      userId: withdrawnOwnerId,
      speciesId,
      latitude: 30.2722,
      longitude: -97.7481,
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
    await insertScan(client, {
      id: moderatedScanId,
      userId: moderatedOwnerId,
      speciesId,
      latitude: 30.3072,
      longitude: -97.7831,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: visiblePostId,
      userId: visibleOwnerId,
      scanId: visibleScanId,
      sharedAt: "2026-04-28T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: withdrawnPostId,
      userId: withdrawnOwnerId,
      scanId: withdrawnScanId,
      sharedAt: "2026-04-28T12:02:00.000Z",
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
    await insertExplorePost(client, {
      id: moderatedPostId,
      userId: moderatedOwnerId,
      scanId: moderatedScanId,
      sharedAt: "2026-04-28T12:20:00.000Z",
    });

    await client.queryArray(
      `
        INSERT INTO public.explore_observation_projection (
          post_id,
          scan_id,
          projection_state
        )
        VALUES ($1, $2, 'withdrawn')
        ON CONFLICT (post_id) DO UPDATE
        SET projection_state = EXCLUDED.projection_state
      `,
      [withdrawnPostId, withdrawnScanId],
    );

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
      "DELETE FROM public.explore_post_media WHERE post_id = $1",
      [mediaClearedPostId],
    );

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET unshared_at = NOW()
        WHERE id = $1
      `,
      [unsharedPostId],
    );
    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET moderated_at = NOW()
        WHERE id = $1
      `,
      [moderatedPostId],
    );

    const rows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed($1, 20, NULL, NULL)
      `,
      [viewerId],
    );

    assertEquals(rows.rows.map((row) => row.post_id), [
      withdrawnPostId,
      visiblePostId,
    ]);
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

      for (
        let likeIndex = 0;
        likeIndex < posts[index].likeCount;
        likeIndex += 1
      ) {
        const likerId = crypto.randomUUID();
        await insertUser(
          client,
          likerId,
          `Trending Liker ${index}-${likeIndex}`,
        );
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

    const oneMileRows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed_nearby(
          self_id => $1,
          viewer_latitude => 30.2672,
          viewer_longitude => -97.7431,
          nearby_radius_miles => 1
        )
      `,
      [viewerId],
    );

    assertEquals(
      oneMileRows.rows.map((row) => row.post_id),
      [nearbyOlderPostId],
    );
  });
});

Deno.test("Explore nearby feed DB - uses post-level public coordinates", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const privateScanOpenPostScanId = crypto.randomUUID();
    const openScanObscuredPostScanId = crypto.randomUUID();
    const privateScanOpenPostId = crypto.randomUUID();
    const openScanObscuredPostId = crypto.randomUUID();

    await insertUser(client, ownerId, "Nearby Override Owner");
    await insertUser(client, viewerId, "Nearby Override Viewer");
    await insertSpecies(client, speciesId, "Rosa overrideis");

    await insertScan(client, {
      id: privateScanOpenPostScanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "private",
    });
    await insertScan(client, {
      id: openScanObscuredPostScanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2673,
      longitude: -97.7432,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: privateScanOpenPostId,
      userId: ownerId,
      scanId: privateScanOpenPostScanId,
      locationSharing: "open",
      sharedAt: "2026-04-28T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: openScanObscuredPostId,
      userId: ownerId,
      scanId: openScanObscuredPostScanId,
      locationSharing: "obscured",
      sharedAt: "2026-04-28T12:10:00.000Z",
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
      [privateScanOpenPostId],
    );
  });
});

Deno.test("Explore feed DB - advanced filters compose before pagination", async () => {
  await withExploreDbTest("exploreFeedDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const plantSpeciesId = crypto.randomUUID();
    const birdSpeciesId = crypto.randomUUID();
    const plantScanId = crypto.randomUUID();
    const recentBirdScanId = crypto.randomUUID();
    const oldBirdScanId = crypto.randomUUID();
    const plantPostId = crypto.randomUUID();
    const recentBirdPostId = crypto.randomUUID();
    const oldBirdPostId = crypto.randomUUID();

    await insertUser(client, ownerId, "Advanced Filter Owner");
    await insertUser(client, viewerId, "Advanced Filter Viewer");
    await insertSpecies(client, plantSpeciesId, "Rosa filteris");
    await insertSpecies(client, birdSpeciesId, "Avis filteris");
    await client.queryArray(
      `
        UPDATE public.species_dictionary
        SET kingdom = 'Animalia', class = 'Aves'
        WHERE id = $1
      `,
      [birdSpeciesId],
    );

    for (
      const [scanId, speciesId] of [
        [plantScanId, plantSpeciesId],
        [recentBirdScanId, birdSpeciesId],
        [oldBirdScanId, birdSpeciesId],
      ]
    ) {
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });
    }

    await insertExplorePost(client, {
      id: plantPostId,
      userId: ownerId,
      scanId: plantScanId,
      sharedAt: "2026-07-12T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: recentBirdPostId,
      userId: ownerId,
      scanId: recentBirdScanId,
      sharedAt: "2026-07-10T12:00:00.000Z",
    });
    await insertExplorePost(client, {
      id: oldBirdPostId,
      userId: ownerId,
      scanId: oldBirdScanId,
      sharedAt: "2026-05-10T12:00:00.000Z",
    });

    await client.queryArray(
      `
        UPDATE public.explore_post_media
        SET kind = 'video', has_audio = TRUE
        WHERE post_id IN ($1, $2)
      `,
      [recentBirdPostId, oldBirdPostId],
    );

    const rows = await client.queryObject<ExploreFeedRow>(
      `
        SELECT post_id, shared_at::text AS shared_at
        FROM public.get_explore_feed(
          self_id => $1,
          requested_species_categories => ARRAY['birds']::text[],
          requested_media_types => ARRAY['video']::text[],
          shared_since => '2026-07-01T00:00:00.000Z'::timestamptz
        )
      `,
      [viewerId],
    );

    assertEquals(rows.rows.map((row) => row.post_id), [recentBirdPostId]);
  });
});
