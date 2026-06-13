import {
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ScanGeoprivacyProjection = {
  geoprivacy: "open" | "obscured" | "private";
  gps_lat_public: number | null;
  gps_long_public: number | null;
  coordinate_uncertainty_in_meters: number | null;
  public_location_label: string | null;
};

async function fetchProjection(
  client: Client,
  scanId: string,
): Promise<ScanGeoprivacyProjection> {
  const result = await client.queryObject<ScanGeoprivacyProjection>(
    `
      SELECT
        geoprivacy::text AS geoprivacy,
        gps_lat_public,
        gps_long_public,
        coordinate_uncertainty_in_meters,
        public_location_label
      FROM public.scans
      WHERE id = $1
    `,
    [scanId],
  );

  const row = result.rows[0];
  if (!row) {
    throw new Error("Expected scan projection row");
  }

  return row;
}

Deno.test("Geoprivacy DB - changing the user default reprojects existing scan locations", async () => {
  await withExploreDbTest("geoprivacyDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();

    await insertUser(client, ownerId, "Geo Privacy");
    await insertSpecies(client, speciesId, "Rosa privata");
    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
      gpsLatPublic: null,
      gpsLongPublic: null,
      semanticLocation: "Austin, Texas",
      publicLocationLabel: "Austin, Texas",
    });

    let projection = await fetchProjection(client, scanId);
    assertEquals(projection.geoprivacy, "open");
    assertAlmostEquals(projection.gps_lat_public ?? 0, 30.2672, 0.0001);
    assertAlmostEquals(projection.gps_long_public ?? 0, -97.7431, 0.0001);
    assertEquals(projection.public_location_label, "Austin, Texas");

    await client.queryArray(
      "UPDATE public.users SET default_geoprivacy = 'private' WHERE id = $1",
      [ownerId],
    );

    projection = await fetchProjection(client, scanId);
    assertEquals(projection.geoprivacy, "private");
    assertEquals(projection.gps_lat_public, null);
    assertEquals(projection.gps_long_public, null);
    assertEquals(projection.coordinate_uncertainty_in_meters, null);
    assertEquals(projection.public_location_label, null);

    await client.queryArray(
      "UPDATE public.users SET default_geoprivacy = 'obscured' WHERE id = $1",
      [ownerId],
    );

    projection = await fetchProjection(client, scanId);
    assertEquals(projection.geoprivacy, "obscured");
    assertAlmostEquals(projection.gps_lat_public ?? 0, 30.3, 0.0001);
    assertAlmostEquals(projection.gps_long_public ?? 0, -97.7, 0.0001);
    assertEquals(projection.coordinate_uncertainty_in_meters, 10000);
    assertEquals(projection.public_location_label, "Austin, Texas");
  });
});
