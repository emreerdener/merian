import { assertAlmostEquals, assertEquals, assertExists } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";
import { publicSpeciesProjectionForbiddenKeys } from "../_shared/publicSpeciesProjection.ts";

type ExplorePostDetailRow = {
  post_id: string;
  field_notes: string | null;
  location_sharing?: "open" | "obscured" | "private";
  hashtags: string[];
  alternative_common_names: string[];
  ai_reasoning: string | null;
  gbif_taxon_key: number | null;
  hazard_type: string | null;
  wikipedia_url: string | null;
  reference_image_url: string | null;
  wikipedia_overview: string | null;
  similar_species: ExplorePostDetailSimilarSpecies[] | null;
  map_point?: ExplorePostDetailMapPoint | null;
};

type ExplorePostDetailMapPoint = {
  latitude: number;
  longitude: number;
  coordinate_visibility: "exact" | "obscured";
};

type ExplorePostDetailSimilarSpecies = {
  species_id: string;
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
  reason: string | null;
  visual_traits: string[];
  confidence: number | null;
  source: string | null;
  review_status: string | null;
  is_bidirectional: boolean;
  sort_order: number | null;
};

Deno.test("Explore post detail DB - returns cached reference imagery with the public detail payload", async () => {
  await withExploreDbTest(
    "explorePostDetailDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const lookalikeId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const wikipediaUrl = "https://en.wikipedia.org/wiki/Rosa_galeria";
      const referenceImageUrl = [
        "https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Rosa_galeria.jpg/640px-Rosa_galeria.jpg",
        "https://inaturalist-open-data.s3.amazonaws.com/photos/123/original.jpg",
        "https://inaturalist-open-data.s3.amazonaws.com/photos/456/original.jpg",
      ].join(",");
      const normalizedReferenceImageUrl = [
        "https://normalized.example.com/rosa-galeria-hero.jpg",
        "https://normalized.example.com/rosa-galeria-secondary.jpg",
      ].join(",");
      const normalizedLookalikeImageUrl =
        "https://normalized.example.com/rosa-minor.jpg";

      await insertUser(client, ownerId, "Gallery Owner");
      await insertUser(client, viewerId, "Gallery Viewer");
      await insertSpecies(client, speciesId, "Rosa galeria");
      await insertSpecies(client, lookalikeId, "Rosa minor");

      await client.queryArray(
        `
        UPDATE public.species_dictionary
        SET
          wikipedia_url = $2,
          reference_image_url = $3,
          wikipedia_overview = $4,
          gbif_taxon_key = $5,
          alternative_common_names = $6,
          hazard_type = $7
        WHERE id = $1
      `,
        [
          speciesId,
          wikipediaUrl,
          referenceImageUrl,
          "Rosa galeria is a test species used to validate Explore detail payload enrichment.",
          424242,
          ["Garden Rose", "Meadow Rose"],
          "poisonous",
        ],
      );

      await client.queryArray(
        `
        UPDATE public.species_dictionary
        SET
          common_names = $2::jsonb,
          reference_image_url = $3,
          iucn_red_list_status = $4
        WHERE id = $1
      `,
        [
          lookalikeId,
          '{"en":"Small Rose"}',
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Rosa_minor.jpg/640px-Rosa_minor.jpg,https://inaturalist-open-data.s3.amazonaws.com/photos/789/original.jpg",
          "least_concern",
        ],
      );

      await client.queryArray(
        `
        INSERT INTO public.species_reference_images (
          species_id,
          url,
          source,
          sort_order,
          license,
          attribution
        )
        VALUES
          ($1, 'https://normalized.example.com/rosa-galeria-secondary.jpg', 'gbif', 1, 'CC BY 4.0', 'Secondary Tester'),
          ($1, 'https://normalized.example.com/rosa-galeria-hero.jpg', 'wikipedia', 0, 'CC BY-SA 4.0', 'Hero Tester'),
          ($2, $3, 'gbif', 0, NULL, NULL)
        ON CONFLICT DO NOTHING
      `,
        [speciesId, lookalikeId, normalizedLookalikeImageUrl],
      );

      await client.queryArray(
        `
        INSERT INTO public.species_lookalikes (
          species_id,
          lookalike_id,
          reason,
          visual_traits,
          confidence,
          source,
          sort_order
        )
        VALUES (
          $1,
          $2,
          'Similar flower shape and thorn spacing.',
          ARRAY['pink flowers', 'compound leaves'],
          0.8200,
          'model_enrichment',
          0
        )
        ON CONFLICT (species_id, lookalike_id) DO UPDATE
        SET reason = EXCLUDED.reason,
            visual_traits = EXCLUDED.visual_traits,
            confidence = EXCLUDED.confidence,
            source = EXCLUDED.source,
            sort_order = EXCLUDED.sort_order
      `,
        [speciesId, lookalikeId],
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
        fieldNotes: "Found near the shaded edge of the trail after rain.",
      });

      await client.queryArray(
        `
        INSERT INTO public.explore_post_hashtags (post_id, tag)
        VALUES ($1, 'springcount'), ($1, 'citybioblitz')
      `,
        [postId],
      );

      const result = await client.queryObject<ExplorePostDetailRow>(
        `
        SELECT
          post_id,
          field_notes,
          hashtags,
          alternative_common_names,
          ai_reasoning,
          gbif_taxon_key,
          hazard_type,
          wikipedia_url,
          reference_image_url,
          wikipedia_overview,
          similar_species
        FROM public.get_explore_post_detail($1, $2)
      `,
        [viewerId, postId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.post_id, postId);
      assertEquals(
        row.field_notes,
        "Found near the shaded edge of the trail after rain.",
      );
      assertEquals(row.hashtags, ["citybioblitz", "springcount"]);
      assertEquals(
        row.ai_reasoning,
        "Petal shape and thorn spacing match Rosa galeria.",
      );
      assertEquals(row.alternative_common_names, [
        "Garden Rose",
        "Meadow Rose",
      ]);
      assertEquals(row.gbif_taxon_key, 424242);
      assertEquals(row.hazard_type, "poisonous");
      assertEquals(row.wikipedia_url, wikipediaUrl);
      assertEquals(row.reference_image_url, normalizedReferenceImageUrl);
      assertEquals(
        row.wikipedia_overview,
        "Rosa galeria is a test species used to validate Explore detail payload enrichment.",
      );
      assertEquals(row.similar_species?.length, 1);
      assertEquals(row.similar_species?.[0], {
        species_id: lookalikeId,
        scientific_name: "Rosa minor",
        common_name: "Small Rose",
        reference_image_url: normalizedLookalikeImageUrl,
        iucn_red_list_status: "least_concern",
        reason: "Similar flower shape and thorn spacing.",
        visual_traits: ["pink flowers", "compound leaves"],
        confidence: 0.82,
        source: "model_enrichment",
        review_status: "unreviewed",
        is_bidirectional: false,
        sort_order: 0,
      });
      assertEquals(
        publicSpeciesProjectionForbiddenKeys(row.similar_species),
        [],
      );
    },
  );
});

Deno.test("Explore post detail DB - returns an empty similar_species array when no lookalikes exist", async () => {
  await withExploreDbTest(
    "explorePostDetailDb.noLookalikes.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();

      await insertUser(client, ownerId, "Sparse Owner");
      await insertUser(client, viewerId, "Sparse Viewer");
      await insertSpecies(client, speciesId, "Rosa sparsa");

      await client.queryArray(
        "DELETE FROM public.species_lookalikes WHERE species_id = $1",
        [speciesId],
      );

      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
      });

      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
      });

      const result = await client.queryObject<ExplorePostDetailRow>(
        `
        SELECT post_id, alternative_common_names, similar_species
        FROM public.get_explore_post_detail($1, $2)
      `,
        [viewerId, postId],
      );

      const row = result.rows[0];
      assertExists(row);
      assertEquals(row.post_id, postId);
      assertEquals(row.alternative_common_names, []);
      assertEquals(row.similar_species, []);
    },
  );
});

Deno.test("Explore post detail DB - excludes only the current scan media from references", async () => {
  await withExploreDbTest(
    "explorePostDetailDb.currentScanReferenceDeduplication.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const currentPhoto =
        "https://media.merian.app/public_uploads/pro/owner/current.webp";
      const currentVideoFrame =
        "https://media.merian.app/public_uploads/pro/owner/frame.webp";
      const otherCommunityPhoto =
        "https://media.merian.app/public_uploads/pro/other/reference.webp";
      const wikipediaPhoto = "https://upload.wikimedia.org/species.jpg";

      await insertUser(client, ownerId, "Reference Owner");
      await insertUser(client, viewerId, "Reference Viewer");
      await insertSpecies(client, speciesId, "Rosa distincta");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrls: [currentPhoto, currentVideoFrame],
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
      });

      await client.queryArray(
        `
          INSERT INTO public.species_reference_images (
            species_id,
            url,
            source,
            sort_order
          )
          VALUES
            ($1, $2, 'merian', 0),
            ($1, $3, 'merian', 1),
            ($1, $4, 'merian', 2),
            ($1, $5, 'wikipedia', 0)
          ON CONFLICT DO NOTHING
        `,
        [
          speciesId,
          currentPhoto,
          currentVideoFrame,
          otherCommunityPhoto,
          wikipediaPhoto,
        ],
      );

      const result = await client.queryObject<ExplorePostDetailRow>(
        `
          SELECT post_id, reference_image_url
          FROM public.get_explore_post_detail($1, $2)
        `,
        [viewerId, postId],
      );

      assertEquals(result.rows[0]?.post_id, postId);
      assertEquals(
        result.rows[0]?.reference_image_url,
        [otherCommunityPhoto, wikipediaPhoto].join(","),
      );

      const legacyFallback = await client.queryObject<{ urls: string | null }>(
        `
          SELECT public.public_species_reference_image_urls_excluding_media(
            $1,
            $2,
            $3::TEXT[]
          ) AS urls
        `,
        [
          crypto.randomUUID(),
          [currentPhoto, wikipediaPhoto].join(","),
          [currentPhoto],
        ],
      );
      assertEquals(legacyFallback.rows[0]?.urls, wikipediaPhoto);
    },
  );
});

Deno.test("Explore post detail DB - gates post-owned map points by current location sharing", async () => {
  await withExploreDbTest(
    "explorePostDetailDb.mapPoint.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const viewerId = crypto.randomUUID();
      const exactSpeciesId = crypto.randomUUID();
      const protectedSpeciesId = crypto.randomUUID();
      const exactScanId = crypto.randomUUID();
      const protectedScanId = crypto.randomUUID();
      const exactPostId = crypto.randomUUID();
      const protectedPostId = crypto.randomUUID();

      await insertUser(client, ownerId, "Map Point Owner");
      await insertUser(client, viewerId, "Map Point Viewer");
      await insertSpecies(client, exactSpeciesId, "Contractus exactus");
      await insertSpecies(
        client,
        protectedSpeciesId,
        "Contractus protectus",
        "vulnerable",
      );

      await insertScan(client, {
        id: exactScanId,
        userId: ownerId,
        speciesId: exactSpeciesId,
        latitude: 12.3456,
        longitude: -45.6789,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: exactPostId,
        userId: ownerId,
        scanId: exactScanId,
        locationSharing: "open",
      });

      await insertScan(client, {
        id: protectedScanId,
        userId: ownerId,
        speciesId: protectedSpeciesId,
        latitude: -23.4567,
        longitude: 67.8912,
        geoprivacy: "open",
      });
      await insertExplorePost(client, {
        id: protectedPostId,
        userId: ownerId,
        scanId: protectedScanId,
        locationSharing: "open",
      });

      const fetchMapPoint = async (postId: string) => {
        const result = await client.queryObject<ExplorePostDetailRow>(
          `
            SELECT post_id, location_sharing, map_point
            FROM public.get_explore_post_detail($1, $2)
          `,
          [viewerId, postId],
        );
        return result.rows[0];
      };

      const exact = await fetchMapPoint(exactPostId);
      assertExists(exact);
      assertEquals(exact.location_sharing, "open");
      assertEquals(exact.map_point?.coordinate_visibility, "exact");
      assertAlmostEquals(exact.map_point?.latitude ?? 0, 12.3456, 0.0001);
      assertAlmostEquals(exact.map_point?.longitude ?? 0, -45.6789, 0.0001);

      const protectedPoint = await fetchMapPoint(protectedPostId);
      assertExists(protectedPoint);
      assertEquals(protectedPoint.location_sharing, "open");
      assertEquals(
        protectedPoint.map_point?.coordinate_visibility,
        "obscured",
      );
      assertAlmostEquals(
        protectedPoint.map_point?.latitude ?? 0,
        -23.5,
        0.0001,
      );
      assertAlmostEquals(
        protectedPoint.map_point?.longitude ?? 0,
        67.9,
        0.0001,
      );

      for (const locationSharing of ["obscured", "private"] as const) {
        await client.queryArray(
          `
            UPDATE public.explore_posts
            SET location_sharing = $2
            WHERE id = $1
          `,
          [exactPostId, locationSharing],
        );
        const hidden = await fetchMapPoint(exactPostId);
        assertExists(hidden);
        assertEquals(hidden.location_sharing, locationSharing);
        assertEquals(hidden.map_point, null);
      }

      await client.queryArray(
        `
          UPDATE public.explore_posts
          SET location_sharing = 'open'
          WHERE id = $1
        `,
        [exactPostId],
      );
      const restored = await fetchMapPoint(exactPostId);
      assertExists(restored);
      assertEquals(restored.location_sharing, "open");
      assertEquals(restored.map_point?.coordinate_visibility, "exact");
    },
  );
});
