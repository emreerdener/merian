import {
  assertAlmostEquals,
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL") ?? DEFAULT_DB_URL;

async function withDbTest(
  fn: (client: Client) => Promise<void>,
): Promise<void> {
  const client = new Client(DB_URL);

  try {
    await client.connect();
  } catch (error) {
    console.warn(
      `[exploreMapDb.test] Skipping DB integration test. Could not connect to ${DB_URL}: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return;
  }

  try {
    await client.queryArray("BEGIN");
    await fn(client);
  } finally {
    try {
      await client.queryArray("ROLLBACK");
    } catch {
      // Ignore rollback failures during cleanup.
    }
    await client.end();
  }
}

async function insertUser(
  client: Client,
  id: string,
  publicName: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source
      )
      VALUES ($1, $2, $3, 'alias')
    `,
    [id, `${publicName.toLowerCase().replaceAll(" ", "_")}@example.com`, publicName],
  );
}

async function insertSpecies(
  client: Client,
  id: string,
  scientificName: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.species_dictionary (
        id,
        scientific_name,
        common_names,
        kingdom,
        phylum,
        class,
        "order",
        family,
        genus,
        descriptions,
        native_region,
        iucn_red_list_status
      )
      VALUES (
        $1,
        $2,
        '{"en":"Test Species"}'::jsonb,
        'Plantae',
        'Tracheophyta',
        'Magnoliopsida',
        'Rosales',
        'Rosaceae',
        'Rosa',
        '{}'::jsonb,
        'North America',
        'least_concern'
      )
    `,
    [id, scientificName],
  );
}

async function insertExplorePost(
  client: Client,
  id: string,
  userId: string,
  scanId: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.explore_posts (
        id,
        user_id,
        scan_id
      )
      VALUES ($1, $2, $3)
    `,
    [id, userId, scanId],
  );
}

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
  await withDbTest(async (client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Austin Owner");
    await insertUser(client, viewerId, "Austin Viewer");
    await insertSpecies(client, speciesId, "Rosa austinensis");

    await client.queryArray(
      `
        INSERT INTO public.scans (
          id,
          user_id,
          species_id,
          image_storage_urls,
          ai_confidence_score,
          gps_lat_exact,
          gps_long_exact,
          gps_lat_public,
          gps_long_public,
          geoprivacy
        )
        VALUES (
          $1,
          $2,
          $3,
          ARRAY['https://media.merian.app/test-image.webp'],
          0.91,
          30.2672,
          -97.7431,
          NULL,
          NULL,
          'open'
        )
      `,
      [scanId, ownerId, speciesId],
    );

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

    await insertExplorePost(client, postId, ownerId, scanId);

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
  await withDbTest(async (client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, ownerId, "Obscured Owner");
    await insertUser(client, viewerId, "Obscured Viewer");
    await insertSpecies(client, speciesId, "Rosa obscura");

    await client.queryArray(
      `
        INSERT INTO public.scans (
          id,
          user_id,
          species_id,
          image_storage_urls,
          ai_confidence_score,
          gps_lat_exact,
          gps_long_exact,
          gps_lat_public,
          gps_long_public,
          geoprivacy
        )
        VALUES (
          $1,
          $2,
          $3,
          ARRAY['https://media.merian.app/test-image.webp'],
          0.88,
          30.2672,
          -97.7431,
          NULL,
          NULL,
          'obscured'
        )
      `,
      [scanId, ownerId, speciesId],
    );

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

    await insertExplorePost(client, postId, ownerId, scanId);

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
