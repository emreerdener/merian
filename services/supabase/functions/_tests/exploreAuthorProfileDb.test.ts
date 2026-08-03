import { assertEquals, assertExists } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ExploreAuthorProfileRow = {
  author_user_id: string;
  species_count: number;
  current_streak: number;
  heatmap: {
    total_captures: number;
    current_month_captures: number;
    weeks: unknown[];
  };
  awards: Array<{ type: string; current_count: number }>;
  published_post_count: number;
  follower_count: number;
  following_count: number;
  viewer_is_following: boolean;
  preview_posts: Array<{ post_id: string; scan_id: string }>;
};

type ExploreAuthorPostRow = {
  post_id: string;
};

type ExploreOwnerPublicationSummaryRow = {
  publication_intent_count: number;
  visible_post_count: number;
  recovery_needed_post_count: number;
  degraded_post_count: number;
  quarantined_post_count: number;
};

Deno.test("Explore author profile DB - private scans contribute to aggregates but not published preview", async () => {
  await withExploreDbTest(
    "exploreAuthorProfileDb.test",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const publicSpeciesId = crypto.randomUUID();
      const privateSpeciesId = crypto.randomUUID();
      const dogSpeciesId = crypto.randomUUID();
      const publicScanId = crypto.randomUUID();
      const quarantinedScanId = crypto.randomUUID();
      const privateScanId = crypto.randomUUID();
      const dogScanId = crypto.randomUUID();
      const publicPostId = crypto.randomUUID();
      const quarantinedPostId = crypto.randomUUID();
      const otherFollowerId = crypto.randomUUID();
      const authorFolloweeId = crypto.randomUUID();

      await insertUser(client, viewerId, "Profile Viewer");
      await insertUser(client, authorId, "Profile Author");
      await insertUser(client, otherFollowerId, "Other Follower");
      await insertUser(client, authorFolloweeId, "Author Followee");
      await insertSpecies(client, publicSpeciesId, "Rosa publica");
      await insertSpecies(client, privateSpeciesId, "Rosa privata");
      await insertSpecies(client, dogSpeciesId, "Canis lupus familiaris");

      await client.queryArray(
        `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2), ($3, $2), ($2, $4)
      `,
        [viewerId, authorId, otherFollowerId, authorFolloweeId],
      );

      await insertScan(client, {
        id: publicScanId,
        userId: authorId,
        speciesId: publicSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });
      await client.queryArray(
        `
        UPDATE public.scans
        SET timestamp = NOW(), device_time_zone = 'UTC'
        WHERE id = $1
      `,
        [publicScanId],
      );
      await insertExplorePost(client, {
        id: publicPostId,
        userId: authorId,
        scanId: publicScanId,
        sharedAt: "2026-05-10T12:00:00.000Z",
      });

      await insertScan(client, {
        id: quarantinedScanId,
        userId: authorId,
        speciesId: publicSpeciesId,
        latitude: 30.2673,
        longitude: -97.7432,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: quarantinedPostId,
        userId: authorId,
        scanId: quarantinedScanId,
        sharedAt: "2026-05-11T12:00:00.000Z",
      });
      await client.queryArray(
        `
        UPDATE public.explore_post_media
        SET health_status = 'missing',
            missing_confirmed_at = NOW(),
            consecutive_missing_checks = 2
        WHERE post_id = $1
      `,
        [quarantinedPostId],
      );
      await client.queryArray(
        `
        UPDATE public.explore_posts
        SET media_health_status = 'quarantined',
            missing_media_count = total_media_count,
            media_quarantined_at = NOW()
        WHERE id = $1
      `,
        [quarantinedPostId],
      );

      await insertScan(client, {
        id: privateScanId,
        userId: authorId,
        speciesId: privateSpeciesId,
        latitude: 30.2,
        longitude: -97.7,
        geoprivacy: "private",
      });
      await client.queryArray(
        `
        UPDATE public.scans
        SET timestamp = NOW() - INTERVAL '1 day', device_time_zone = 'UTC'
        WHERE id = $1
      `,
        [privateScanId],
      );

      await insertScan(client, {
        id: dogScanId,
        userId: authorId,
        speciesId: dogSpeciesId,
        latitude: 30.3,
        longitude: -97.6,
        geoprivacy: "private",
      });
      await client.queryArray(
        `
        UPDATE public.scans
        SET timestamp = NOW() - INTERVAL '2 days', device_time_zone = 'UTC'
        WHERE id = $1
      `,
        [dogScanId],
      );

      const result = await client.queryObject<ExploreAuthorProfileRow>(
        `
        SELECT *
        FROM public.get_explore_author_profile($1, $2, 9)
      `,
        [viewerId, authorId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.author_user_id, authorId);
      assertEquals(row.species_count, 3);
      assertEquals(row.current_streak, 3);
      assertEquals(row.heatmap.total_captures, 4);
      assertEquals(row.published_post_count, 1);
      assertEquals(row.follower_count, 2);
      assertEquals(row.following_count, 1);
      assertEquals(row.viewer_is_following, true);
      assertEquals(row.preview_posts.map((post) => post.post_id), [
        publicPostId,
      ]);

      const ownerSummary = await client
        .queryObject<ExploreOwnerPublicationSummaryRow>(
          `
          SELECT *
          FROM public.get_owned_explore_publication_summary($1)
        `,
          [authorId],
        );
      assertEquals(ownerSummary.rows, [{
        publication_intent_count: 2,
        visible_post_count: 1,
        recovery_needed_post_count: 1,
        degraded_post_count: 0,
        quarantined_post_count: 1,
      }]);
      assertEquals(
        row.awards.find((award) => award.type === "explorer")?.current_count,
        3,
      );
      assertEquals(
        row.awards.find((award) => award.type === "domestic_dog")
          ?.current_count,
        1,
      );
      assertEquals(
        row.awards.find((award) => award.type === "domestic_cat")
          ?.current_count,
        0,
      );
    },
  );
});

Deno.test("Explore author profile DB - owner can inspect a fully quarantined publication set without making it public", async () => {
  await withExploreDbTest(
    "exploreAuthorProfileDb.test",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();

      await insertUser(client, viewerId, "Quarantine Viewer");
      await insertUser(client, authorId, "Quarantine Author");
      // New accounts are auto-enrolled in a profile-visible starter trip.
      // Keep this fixture focused on Explore publication visibility.
      await client.queryArray(
        `
        UPDATE public.user_field_trips
        SET is_profile_visible = FALSE
        WHERE user_id = $1
      `,
        [authorId],
      );
      await insertSpecies(client, speciesId, "Rosa quarantina");
      await insertScan(client, {
        id: scanId,
        userId: authorId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: postId,
        userId: authorId,
        scanId,
        sharedAt: "2026-07-26T12:00:00.000Z",
      });
      await client.queryArray(
        `
        UPDATE public.explore_post_media
        SET health_status = 'missing',
            missing_confirmed_at = NOW(),
            consecutive_missing_checks = 2
        WHERE post_id = $1
      `,
        [postId],
      );
      await client.queryArray(
        `
        UPDATE public.explore_posts
        SET media_health_status = 'quarantined',
            missing_media_count = total_media_count,
            media_quarantined_at = NOW()
        WHERE id = $1
      `,
        [postId],
      );

      const ownerProfile = await client.queryObject<ExploreAuthorProfileRow>(
        `
        SELECT *
        FROM public.get_explore_author_profile($1, $1, 9)
      `,
        [authorId],
      );
      assertEquals(ownerProfile.rows.length, 1);
      assertEquals(ownerProfile.rows[0].published_post_count, 0);
      assertEquals(ownerProfile.rows[0].preview_posts, []);

      const publicProfile = await client.queryObject<ExploreAuthorProfileRow>(
        `
        SELECT *
        FROM public.get_explore_author_profile($1, $2, 9)
      `,
        [viewerId, authorId],
      );
      assertEquals(publicProfile.rows, []);
    },
  );
});

Deno.test("Explore author posts DB - excludes media-empty, unshared, tombstoned, and paginates by cursor", async () => {
  await withExploreDbTest(
    "exploreAuthorProfileDb.test",
    async (client: Client) => {
      const viewerId = crypto.randomUUID();
      const authorId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();

      await insertUser(client, viewerId, "Library Viewer");
      await insertUser(client, authorId, "Library Author");
      await insertSpecies(client, speciesId, "Rosa libraria");

      const visiblePostIds = [
        "00000000-0000-0000-0000-000000000111",
        "00000000-0000-0000-0000-000000000222",
      ];
      const visibleScanIds = [crypto.randomUUID(), crypto.randomUUID()];

      for (let index = 0; index < visibleScanIds.length; index += 1) {
        await insertScan(client, {
          id: visibleScanIds[index],
          userId: authorId,
          speciesId,
          latitude: 30.2672 + index,
          longitude: -97.7431 - index,
          geoprivacy: "open",
        });
        await insertExplorePost(client, {
          id: visiblePostIds[index],
          userId: authorId,
          scanId: visibleScanIds[index],
          sharedAt: index === 0
            ? "2026-05-10T12:00:00.000Z"
            : "2026-05-09T12:00:00.000Z",
        });
      }

      const mediaEmptyScanId = crypto.randomUUID();
      const unsharedScanId = crypto.randomUUID();
      const tombstonedScanId = crypto.randomUUID();
      await insertScan(client, {
        id: mediaEmptyScanId,
        userId: authorId,
        speciesId,
        latitude: 30.1,
        longitude: -97.1,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: authorId,
        scanId: mediaEmptyScanId,
        sharedAt: "2026-05-11T12:00:00.000Z",
        refreshMedia: false,
      });

      await insertScan(client, {
        id: unsharedScanId,
        userId: authorId,
        speciesId,
        latitude: 30.2,
        longitude: -97.2,
        geoprivacy: "open",
      });
      const unsharedPostId = crypto.randomUUID();
      await insertExplorePost(client, {
        id: unsharedPostId,
        userId: authorId,
        scanId: unsharedScanId,
        sharedAt: "2026-05-11T11:00:00.000Z",
      });
      await client.queryArray(
        "UPDATE public.explore_posts SET unshared_at = NOW() WHERE id = $1",
        [unsharedPostId],
      );

      await insertScan(client, {
        id: tombstonedScanId,
        userId: authorId,
        speciesId,
        latitude: 30.3,
        longitude: -97.3,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: authorId,
        scanId: tombstonedScanId,
        sharedAt: "2026-05-11T10:00:00.000Z",
      });
      await client.queryArray(
        "UPDATE public.scans SET is_tombstoned = TRUE WHERE id = $1",
        [tombstonedScanId],
      );

      const firstPage = await client.queryObject<ExploreAuthorPostRow>(
        `
        SELECT post_id
        FROM public.get_explore_author_posts($1, $2, 1, NULL, NULL)
      `,
        [viewerId, authorId],
      );

      assertEquals(firstPage.rows.map((row) => row.post_id), [
        visiblePostIds[0],
      ]);

      const secondPage = await client.queryObject<ExploreAuthorPostRow>(
        `
        SELECT post_id
        FROM public.get_explore_author_posts($1, $2, 10, $3::timestamptz, $4::uuid)
      `,
        [viewerId, authorId, "2026-05-10T12:00:00.000Z", visiblePostIds[0]],
      );

      assertEquals(secondPage.rows.map((row) => row.post_id), [
        visiblePostIds[1],
      ]);
    },
  );
});
