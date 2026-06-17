import {
  assertAlmostEquals,
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

type ScanCoordinateRow = {
  gps_lat_public: number | null;
  gps_long_public: number | null;
  coordinate_uncertainty_in_meters: number | null;
};

type ExploreMapRow = {
  post_id: string;
  latitude: number;
  longitude: number;
  coordinate_visibility: "exact" | "obscured";
};

Deno.test("Explore map DB - newly shared scan with exact coordinates is queryable even when public coordinates were omitted at insert time", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Austin Owner");
    await insertUser(client, viewerId, "Austin Viewer");
    await insertSpecies(client, speciesId, "Rosa austinensis");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
      gpsLatPublic: null,
      gpsLongPublic: null,
      aiConfidenceScore: 0.91,
    });

    const insertedScan = await client.queryObject<ScanCoordinateRow>(
      `
        SELECT
          gps_lat_public,
          gps_long_public,
          coordinate_uncertainty_in_meters
        FROM public.scans
        WHERE id = $1
      `,
      [scanId],
    );

    assertExists(insertedScan.rows[0]);
    assertAlmostEquals(
      insertedScan.rows[0].gps_lat_public ?? 0,
      30.2672,
      0.0001,
    );
    assertAlmostEquals(
      insertedScan.rows[0].gps_long_public ?? 0,
      -97.7431,
      0.0001,
    );
    assertEquals(insertedScan.rows[0].coordinate_uncertainty_in_meters, 0);

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
    });

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 1);
    assertEquals(mapRows.rows[0].post_id, postId);
    assertAlmostEquals(mapRows.rows[0].latitude, 30.2672, 0.0001);
    assertAlmostEquals(mapRows.rows[0].longitude, -97.7431, 0.0001);
    assertEquals(mapRows.rows[0].coordinate_visibility, "exact");
  });
});

Deno.test("Explore map DB - obscured post geoprivacy is excluded from map results", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Obscured Owner");
    await insertUser(client, viewerId, "Obscured Viewer");
    await insertSpecies(client, speciesId, "Rosa obscura");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "obscured",
      gpsLatPublic: null,
      gpsLongPublic: null,
      aiConfidenceScore: 0.88,
    });

    const insertedScan = await client.queryObject<ScanCoordinateRow>(
      `
        SELECT
          gps_lat_public,
          gps_long_public,
          coordinate_uncertainty_in_meters
        FROM public.scans
        WHERE id = $1
      `,
      [scanId],
    );

    assertExists(insertedScan.rows[0]);
    assertAlmostEquals(insertedScan.rows[0].gps_lat_public ?? 0, 30.3, 0.0001);
    assertAlmostEquals(
      insertedScan.rows[0].gps_long_public ?? 0,
      -97.7,
      0.0001,
    );
    assertEquals(insertedScan.rows[0].coordinate_uncertainty_in_meters, 10000);

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      locationSharing: "obscured",
    });

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 0);
  });
});

Deno.test("Explore map DB - private post geoprivacy is excluded from map results", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Private Owner");
    await insertUser(client, viewerId, "Private Viewer");
    await insertSpecies(client, speciesId, "Rosa privata");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "private",
      gpsLatPublic: null,
      gpsLongPublic: null,
      aiConfidenceScore: 0.88,
    });

    const insertedScan = await client.queryObject<ScanCoordinateRow>(
      `
        SELECT
          gps_lat_public,
          gps_long_public,
          coordinate_uncertainty_in_meters
        FROM public.scans
        WHERE id = $1
      `,
      [scanId],
    );

    assertExists(insertedScan.rows[0]);
    assertEquals(insertedScan.rows[0].gps_lat_public, null);
    assertEquals(insertedScan.rows[0].gps_long_public, null);
    assertEquals(insertedScan.rows[0].coordinate_uncertainty_in_meters, null);

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      locationSharing: "private",
    });

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 0);
  });
});

Deno.test("Explore map DB - private scan can appear after explicit open post override", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Private Override Owner");
    await insertUser(client, viewerId, "Private Override Viewer");
    await insertSpecies(client, speciesId, "Rosa aperta");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "private",
      gpsLatPublic: null,
      gpsLongPublic: null,
      aiConfidenceScore: 0.88,
      semanticLocation: "Austin, Texas",
    });

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      locationSharing: "private",
    });

    let mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 0);

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET location_sharing = 'open'
        WHERE id = $1
      `,
      [postId],
    );

    mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 1);
    assertEquals(mapRows.rows[0].post_id, postId);
    assertAlmostEquals(mapRows.rows[0].latitude, 30.2672, 0.0001);
    assertAlmostEquals(mapRows.rows[0].longitude, -97.7431, 0.0001);
    assertEquals(mapRows.rows[0].coordinate_visibility, "exact");

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET location_sharing = 'private'
        WHERE id = $1
      `,
      [postId],
    );

    mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 0);
  });
});

Deno.test("Explore map DB - protected open geoprivacy uses rounded public coordinates", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Protected Owner");
    await insertUser(client, viewerId, "Protected Viewer");
    await insertSpecies(client, speciesId, "Rosa vulnerabilis", "vulnerable");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
      gpsLatPublic: null,
      gpsLongPublic: null,
      aiConfidenceScore: 0.88,
    });

    const insertedScan = await client.queryObject<ScanCoordinateRow>(
      `
        SELECT
          gps_lat_public,
          gps_long_public,
          coordinate_uncertainty_in_meters
        FROM public.scans
        WHERE id = $1
      `,
      [scanId],
    );

    assertExists(insertedScan.rows[0]);
    assertAlmostEquals(insertedScan.rows[0].gps_lat_public ?? 0, 30.3, 0.0001);
    assertAlmostEquals(
      insertedScan.rows[0].gps_long_public ?? 0,
      -97.7,
      0.0001,
    );
    assertEquals(insertedScan.rows[0].coordinate_uncertainty_in_meters, 10000);

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
    });

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          30.6,
          30.0,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.length, 1);
    assertEquals(mapRows.rows[0].post_id, postId);
    assertAlmostEquals(mapRows.rows[0].latitude, 30.3, 0.0001);
    assertAlmostEquals(mapRows.rows[0].longitude, -97.7, 0.0001);
    assertEquals(mapRows.rows[0].coordinate_visibility, "obscured");
  });
});

Deno.test("Explore map DB - wrapped longitude queries return discoveries across the dateline", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const easternScanId = crypto.randomUUID();
    const westernScanId = crypto.randomUUID();
    const easternPostId = crypto.randomUUID();
    const westernPostId = crypto.randomUUID();

    await insertUser(client, ownerId, "Dateline Owner");
    await insertUser(client, viewerId, "Dateline Viewer");
    await insertSpecies(client, speciesId, "Rosa datelinis");

    await insertScan(client, {
      id: easternScanId,
      userId: ownerId,
      speciesId,
      latitude: 15.0,
      longitude: 179.6,
      geoprivacy: "open",
    });
    await insertScan(client, {
      id: westernScanId,
      userId: ownerId,
      speciesId,
      latitude: 12.0,
      longitude: -179.7,
      geoprivacy: "open",
    });

    await insertExplorePost(client, {
      id: easternPostId,
      userId: ownerId,
      scanId: easternScanId,
    });
    await insertExplorePost(client, {
      id: westernPostId,
      userId: ownerId,
      scanId: westernScanId,
    });

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          20,
          5,
          -170,
          170,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(
      new Set(mapRows.rows.map((row) => row.post_id)),
      new Set([easternPostId, westernPostId]),
    );
  });
});

Deno.test("Explore map DB - blocked authors and media-cleared scans are excluded from map results", async () => {
  await withExploreDbTest("exploreMapDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const visibleOwnerId = crypto.randomUUID();
    const blockedOwnerId = crypto.randomUUID();
    const mediaClearedOwnerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, viewerId, "Map Viewer");
    await insertUser(client, visibleOwnerId, "Visible Map Owner");
    await insertUser(client, blockedOwnerId, "Blocked Map Owner");
    await insertUser(client, mediaClearedOwnerId, "Media Cleared Map Owner");
    await insertSpecies(client, speciesId, "Rosa mapensis");

    const visibleScanId = crypto.randomUUID();
    const blockedScanId = crypto.randomUUID();
    const mediaClearedScanId = crypto.randomUUID();
    const visiblePostId = crypto.randomUUID();
    const blockedPostId = crypto.randomUUID();
    const mediaClearedPostId = crypto.randomUUID();

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

    await insertExplorePost(client, {
      id: visiblePostId,
      userId: visibleOwnerId,
      scanId: visibleScanId,
    });
    await insertExplorePost(client, {
      id: blockedPostId,
      userId: blockedOwnerId,
      scanId: blockedScanId,
    });
    await insertExplorePost(client, {
      id: mediaClearedPostId,
      userId: mediaClearedOwnerId,
      scanId: mediaClearedScanId,
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

    const mapRows = await client.queryObject<ExploreMapRow>(
      `
        SELECT post_id, latitude, longitude, coordinate_visibility
        FROM public.get_explore_map_posts(
          $1,
          31,
          30,
          -97.4,
          -98.0,
          100
        )
      `,
      [viewerId],
    );

    assertEquals(mapRows.rows.map((row) => row.post_id), [visiblePostId]);
  });
});
