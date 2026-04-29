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
    assertAlmostEquals(insertedScan.rows[0].gps_lat_public ?? 0, 30.2672, 0.0001);
    assertAlmostEquals(insertedScan.rows[0].gps_long_public ?? 0, -97.7431, 0.0001);
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

Deno.test("Explore map DB - obscured geoprivacy projects rounded public coordinates", async () => {
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
    assertAlmostEquals(insertedScan.rows[0].gps_long_public ?? 0, -97.7, 0.0001);
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
