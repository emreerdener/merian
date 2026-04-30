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

type ExplorePostDetailRow = {
  post_id: string;
  ai_reasoning: string | null;
  gbif_taxon_key: number | null;
  wikipedia_url: string | null;
  reference_image_url: string | null;
  wikipedia_overview: string | null;
};

Deno.test("Explore post detail DB - returns cached reference imagery with the public detail payload", async () => {
  await withExploreDbTest("explorePostDetailDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const viewerId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();
    const wikipediaUrl = "https://en.wikipedia.org/wiki/Rosa_galeria";
    const referenceImageUrl = [
      "https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Rosa_galeria.jpg/640px-Rosa_galeria.jpg",
      "https://inaturalist-open-data.s3.amazonaws.com/photos/123/original.jpg",
      "https://inaturalist-open-data.s3.amazonaws.com/photos/456/original.jpg",
    ].join(",");

    await insertUser(client, ownerId, "Gallery Owner");
    await insertUser(client, viewerId, "Gallery Viewer");
    await insertSpecies(client, speciesId, "Rosa galeria");

    await client.queryArray(
      `
        UPDATE public.species_dictionary
        SET
          wikipedia_url = $2,
          reference_image_url = $3,
          wikipedia_overview = $4,
          gbif_taxon_key = $5
        WHERE id = $1
      `,
      [
        speciesId,
        wikipediaUrl,
        referenceImageUrl,
        "Rosa galeria is a test species used to validate Explore detail payload enrichment.",
        424242,
      ],
    );

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });

    await client.queryArray(
      `
        UPDATE public.scans
        SET ai_reasoning = $2
        WHERE id = $1
      `,
      [scanId, "Petal shape and thorn spacing match Rosa galeria."],
    );

    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
    });

    const result = await client.queryObject<ExplorePostDetailRow>(
      `
        SELECT
          post_id,
          ai_reasoning,
          gbif_taxon_key,
          wikipedia_url,
          reference_image_url,
          wikipedia_overview
        FROM public.get_explore_post_detail($1, $2)
      `,
      [viewerId, postId],
    );

    const row = result.rows[0];
    assertExists(row);
    assertEquals(row.post_id, postId);
    assertEquals(row.ai_reasoning, "Petal shape and thorn spacing match Rosa galeria.");
    assertEquals(row.gbif_taxon_key, 424242);
    assertEquals(row.wikipedia_url, wikipediaUrl);
    assertEquals(row.reference_image_url, referenceImageUrl);
    assertEquals(
      row.wikipedia_overview,
      "Rosa galeria is a test species used to validate Explore detail payload enrichment.",
    );
  });
});
