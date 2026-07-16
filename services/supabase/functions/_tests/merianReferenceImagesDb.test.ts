import {
  assert,
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

type RefreshSummary = {
  candidate_count: number;
  promoted_count: number;
  removed_count: number;
  species_count: number;
  dry_run: boolean;
};

type ReferenceImageRow = {
  species_id: string;
  url: string;
  source: string;
  license: string | null;
  attribution: string | null;
  sort_order: number;
};

Deno.test("Merian reference images DB - promotes qualifying published media with cap and confirmed species", async () => {
  await withExploreDbTest(
    "merianReferenceImagesDb.promote.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const lowQualityOwnerId = crypto.randomUUID();
      const privateOwnerId = crypto.randomUUID();
      const shadowOwnerId = crypto.randomUUID();
      const aiSpeciesId = crypto.randomUUID();
      const confirmedSpeciesId = crypto.randomUUID();
      const highScanId = crypto.randomUUID();
      const lowScanId = crypto.randomUUID();
      const privateScanId = crypto.randomUUID();
      const shadowScanId = crypto.randomUUID();

      await insertUser(client, ownerId, "Gallery Owner");
      await insertUser(client, lowQualityOwnerId, "Low Quality Owner");
      await insertUser(client, privateOwnerId, "Private Owner");
      await insertUser(client, shadowOwnerId, "Shadow Owner");
      await client.queryArray(
        "UPDATE public.users SET is_shadowbanned = TRUE WHERE id = $1",
        [shadowOwnerId],
      );
      await insertSpecies(client, aiSpeciesId, "Rosa aiensis");
      await insertSpecies(client, confirmedSpeciesId, "Rosa confirmata");

      const highQualityUrls = Array.from(
        { length: 9 },
        (_, index) =>
          `https://media.merian.app/public_uploads/pro/reference-${index}.webp`,
      );

      await insertScan(client, {
        id: highScanId,
        userId: ownerId,
        speciesId: aiSpeciesId,
        confirmedSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrls: highQualityUrls,
        imageQualityScore: 95,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: ownerId,
        scanId: highScanId,
        sharedAt: "2026-05-13T10:00:00.000Z",
      });

      await insertScan(client, {
        id: lowScanId,
        userId: lowQualityOwnerId,
        speciesId: confirmedSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl: "https://media.merian.app/public_uploads/pro/low.webp",
        imageQualityScore: 79,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: lowQualityOwnerId,
        scanId: lowScanId,
      });

      await insertScan(client, {
        id: privateScanId,
        userId: privateOwnerId,
        speciesId: confirmedSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "private",
        imageUrl: "https://media.merian.app/public_uploads/pro/private.webp",
        imageQualityScore: 99,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: privateOwnerId,
        scanId: privateScanId,
      });

      await insertScan(client, {
        id: shadowScanId,
        userId: shadowOwnerId,
        speciesId: confirmedSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl: "https://media.merian.app/public_uploads/pro/shadow.webp",
        imageQualityScore: 99,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: shadowOwnerId,
        scanId: shadowScanId,
      });

      const summaryResult = await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, FALSE, 0.95)",
      );
      const summary = summaryResult.rows[0];
      assertExists(summary);
      assertEquals(summary.candidate_count, 9);
      assertEquals(summary.promoted_count, 8);
      assertEquals(summary.removed_count, 0);
      assertEquals(summary.species_count, 1);
      assertEquals(summary.dry_run, false);

      const publicRows = await client.queryObject<ReferenceImageRow>(
        `
          SELECT species_id, url, source, license, attribution, sort_order
          FROM public.species_reference_images
          WHERE species_id = $1
          ORDER BY public.public_species_reference_image_source_rank(source), sort_order, created_at, id
        `,
        [confirmedSpeciesId],
      );
      assertEquals(publicRows.rows.length, 8);
      assertEquals(
        publicRows.rows.map((row) => row.url),
        highQualityUrls.slice(0, 8),
      );
      assertEquals(publicRows.rows.map((row) => row.sort_order), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      assert(
        publicRows.rows.every((row) =>
          row.source === "merian" &&
          row.license === "Used with permission via Naturebook" &&
          row.attribution === "Gallery Owner"
        ),
      );

      const aiSpeciesRows = await client.queryObject<{ count: number }>(
        "SELECT COUNT(*)::INTEGER AS count FROM public.species_reference_images WHERE species_id = $1",
        [aiSpeciesId],
      );
      assertEquals(aiSpeciesRows.rows[0].count, 0);

      const sourceRows = await client.queryObject<{
        total: number;
        promoted: number;
        active: number;
        confirmed_sources: number;
      }>(
        `
          SELECT
            COUNT(*)::INTEGER AS total,
            COUNT(*) FILTER (WHERE is_promoted)::INTEGER AS promoted,
            COUNT(*) FILTER (WHERE disqualified_at IS NULL)::INTEGER AS active,
            COUNT(*) FILTER (WHERE species_confidence_source = 'confirmed_species')::INTEGER AS confirmed_sources
          FROM public.species_reference_image_merian_sources
          WHERE species_id = $1
        `,
        [confirmedSpeciesId],
      );
      assertEquals(sourceRows.rows[0], {
        total: 9,
        promoted: 8,
        active: 9,
        confirmed_sources: 9,
      });
    },
  );
});

Deno.test("Merian reference images DB - requires high species confidence and image quality", async () => {
  await withExploreDbTest(
    "merianReferenceImagesDb.confidenceGate.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const aiSpeciesId = crypto.randomUUID();
      const confirmedSpeciesId = crypto.randomUUID();
      const highConfidenceScanId = crypto.randomUUID();
      const lowConfidenceScanId = crypto.randomUUID();
      const lowQualityScanId = crypto.randomUUID();
      const confirmedScanId = crypto.randomUUID();

      await insertUser(client, ownerId, "Confidence Owner");
      await insertSpecies(client, aiSpeciesId, "Rosa confidenta");
      await insertSpecies(client, confirmedSpeciesId, "Rosa verifieda");

      await insertScan(client, {
        id: highConfidenceScanId,
        userId: ownerId,
        speciesId: aiSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl: "https://media.merian.app/public_uploads/pro/high-both.webp",
        aiConfidenceScore: 0.96,
        imageQualityScore: 92,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: ownerId,
        scanId: highConfidenceScanId,
      });

      await insertScan(client, {
        id: lowConfidenceScanId,
        userId: ownerId,
        speciesId: aiSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl:
          "https://media.merian.app/public_uploads/pro/low-confidence.webp",
        aiConfidenceScore: 0.94,
        imageQualityScore: 99,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: ownerId,
        scanId: lowConfidenceScanId,
      });

      await insertScan(client, {
        id: lowQualityScanId,
        userId: ownerId,
        speciesId: aiSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl:
          "https://media.merian.app/public_uploads/pro/low-quality.webp",
        aiConfidenceScore: 0.99,
        imageQualityScore: 79,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: ownerId,
        scanId: lowQualityScanId,
      });

      await insertScan(client, {
        id: confirmedScanId,
        userId: ownerId,
        speciesId: aiSpeciesId,
        confirmedSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrl:
          "https://media.merian.app/public_uploads/pro/confirmed-low-ai.webp",
        aiConfidenceScore: 0.42,
        imageQualityScore: 93,
      });
      await insertExplorePost(client, {
        id: crypto.randomUUID(),
        userId: ownerId,
        scanId: confirmedScanId,
      });

      const dryRun = await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, TRUE, 0.95)",
      );
      assertEquals(dryRun.rows[0].candidate_count, 2);
      assertEquals(dryRun.rows[0].promoted_count, 2);
      assertEquals(dryRun.rows[0].species_count, 2);
      assertEquals(dryRun.rows[0].dry_run, true);

      const summary = await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, FALSE, 0.95)",
      );
      assertEquals(summary.rows[0].candidate_count, 2);
      assertEquals(summary.rows[0].promoted_count, 2);

      const publicRows = await client.queryObject<ReferenceImageRow>(
        `
          SELECT species_id, url, source, license, attribution, sort_order
          FROM public.species_reference_images
          WHERE species_id IN ($1, $2)
          ORDER BY species_id, sort_order
        `,
        [aiSpeciesId, confirmedSpeciesId],
      );
      assertEquals(
        publicRows.rows.map((row) => row.url).sort(),
        [
          "https://media.merian.app/public_uploads/pro/confirmed-low-ai.webp",
          "https://media.merian.app/public_uploads/pro/high-both.webp",
        ],
      );

      const provenance = await client.queryObject<{
        image_url: string;
        species_confidence_score: number;
        species_confidence_source: string;
      }>(
        `
          SELECT image_url, species_confidence_score, species_confidence_source
          FROM public.species_reference_image_merian_sources
          ORDER BY image_url
        `,
      );
      assertEquals(provenance.rows, [
        {
          image_url:
            "https://media.merian.app/public_uploads/pro/confirmed-low-ai.webp",
          species_confidence_score: 0.42,
          species_confidence_source: "confirmed_species",
        },
        {
          image_url:
            "https://media.merian.app/public_uploads/pro/high-both.webp",
          species_confidence_score: 0.96,
          species_confidence_source: "ai",
        },
      ]);

      await client.queryArray(
        "UPDATE public.scans SET ai_confidence_score = 0.9 WHERE id = $1",
        [highConfidenceScanId],
      );

      const removal = await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, FALSE, 0.95)",
      );
      assertEquals(removal.rows[0].removed_count, 1);

      const afterConfidenceDrop = await client.queryObject<{ count: number }>(
        `
          SELECT COUNT(*)::INTEGER AS count
          FROM public.species_reference_images
          WHERE species_id = $1
            AND source = 'merian'
        `,
        [aiSpeciesId],
      );
      assertEquals(afterConfidenceDrop.rows[0].count, 0);
    },
  );
});

Deno.test("Merian reference images DB - mirrors unshare and external refresh preserves Merian rows", async () => {
  await withExploreDbTest(
    "merianReferenceImagesDb.lifecycle.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const merianUrls = [
        "https://media.merian.app/public_uploads/pro/lifecycle-0.webp",
        "https://media.merian.app/public_uploads/pro/lifecycle-1.webp",
      ];

      await insertUser(client, ownerId, "Lifecycle Owner");
      await insertSpecies(client, speciesId, "Rosa lifecycla");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageUrls: merianUrls,
        aiConfidenceScore: 0.97,
        imageQualityScore: 94,
      });
      await insertExplorePost(client, {
        id: postId,
        userId: ownerId,
        scanId,
        sharedAt: "2026-05-13T11:00:00.000Z",
      });

      await client.queryArray(
        `
          INSERT INTO public.species_reference_images (
            species_id,
            url,
            source,
            license,
            attribution,
            sort_order
          )
          VALUES ($1, $2, 'wikipedia', 'CC BY-SA 4.0', 'Wiki Tester', 0)
        `,
        [speciesId, "https://upload.wikimedia.org/lifecycle.jpg"],
      );

      await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, FALSE, 0.95)",
      );

      const orderedBeforeExternalRefresh = await client.queryObject<
        { urls: string }
      >(
        "SELECT public.public_species_reference_image_urls($1, NULL) AS urls",
        [speciesId],
      );
      assertEquals(
        orderedBeforeExternalRefresh.rows[0].urls.split(",").slice(0, 2),
        merianUrls,
      );

      await client.queryArray(
        `
          SELECT public.replace_species_reference_images(
            $1,
            $2::jsonb
          )
        `,
        [
          speciesId,
          JSON.stringify([
            {
              url: "https://static.inaturalist.org/lifecycle.jpg",
              source: "gbif",
              sort_order: 0,
            },
          ]),
        ],
      );

      const orderedAfterExternalRefresh = await client.queryObject<
        { urls: string }
      >(
        "SELECT public.public_species_reference_image_urls($1, NULL) AS urls",
        [speciesId],
      );
      assertEquals(
        orderedAfterExternalRefresh.rows[0].urls.split(",").slice(0, 2),
        merianUrls,
      );

      const sourceCheck = await client.queryObject<{ merian_count: number }>(
        `
          SELECT COUNT(*)::INTEGER AS merian_count
          FROM public.species_reference_images
          WHERE species_id = $1
            AND source = 'merian'
        `,
        [speciesId],
      );
      assertEquals(sourceCheck.rows[0].merian_count, 2);

      await client.queryArray(
        "UPDATE public.explore_posts SET unshared_at = NOW() WHERE id = $1",
        [postId],
      );

      const removal = await client.queryObject<RefreshSummary>(
        "SELECT * FROM public.refresh_merian_reference_images(80, 8, FALSE, 0.95)",
      );
      assertEquals(removal.rows[0].removed_count, 2);

      const afterUnshare = await client.queryObject<{ merian_count: number }>(
        `
          SELECT COUNT(*)::INTEGER AS merian_count
          FROM public.species_reference_images
          WHERE species_id = $1
            AND source = 'merian'
        `,
        [speciesId],
      );
      assertEquals(afterUnshare.rows[0].merian_count, 0);

      const provenanceAfterUnshare = await client.queryObject<{
        active_count: number;
        promoted_count: number;
      }>(
        `
          SELECT
            COUNT(*) FILTER (WHERE disqualified_at IS NULL)::INTEGER AS active_count,
            COUNT(*) FILTER (WHERE is_promoted)::INTEGER AS promoted_count
          FROM public.species_reference_image_merian_sources
          WHERE species_id = $1
        `,
        [speciesId],
      );
      assertEquals(provenanceAfterUnshare.rows[0], {
        active_count: 0,
        promoted_count: 0,
      });
    },
  );
});
