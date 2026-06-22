import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type SearchRow = {
  taxon_id: string;
  taxonomy_version_id: string;
  scientific_name: string;
};

type ProjectionRow = {
  projection_state: string;
  public_taxon_node_id: string | null;
};

type FeedScopeRow = {
  request_id: string;
  author_user_id: string;
};

type RepairRow = {
  repaired_count: number;
};

type SuggestedTaxon = {
  taxon_id: string;
  scientific_name: string;
  suggestion_source: "ai_initial" | "ai_candidate";
  confidence_score: number | null;
  distinguishing_feature: string | null;
};

type DetailRow = {
  inference_tier: string;
  suggested_taxa: SuggestedTaxon[];
};

Deno.test("Community ID DB - versioned search, queued consensus, and projection graduation", async () => {
  await withExploreDbTest(
    "communityIdentificationDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const identifierA = crypto.randomUUID();
      const identifierB = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const candidateHighSpeciesId = crypto.randomUUID();
      const candidateLowSpeciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const otherScanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const otherPostId = crypto.randomUUID();
      const requestId = crypto.randomUUID();
      const otherRequestId = crypto.randomUUID();

      await insertUser(client, ownerId, "Community Owner");
      await insertUser(client, identifierA, "Identifier A");
      await insertUser(client, identifierB, "Identifier B");
      await insertSpecies(client, speciesId, "Rosa communitatis");
      await insertSpecies(client, candidateHighSpeciesId, "Rosa alternata");
      await insertSpecies(client, candidateLowSpeciesId, "Rosa minor");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        gpsLatPublic: 30.2672,
        gpsLongPublic: -97.7431,
        aiConfidenceScore: 0.97,
        aiReasoning:
          "Visible clustered petals and leaves match the initial taxon.",
        inferenceTier: "pro",
        candidates: [
          {
            scientific_name: "Rosa communitatis",
            common_name: "Community Rose",
            confidence_score: 0.99,
            distinguishing_feature: "same as the initial taxon",
          },
          {
            scientific_name: "Rosa minor",
            common_name: "Little Rose",
            confidence_score: 0.62,
            distinguishing_feature: "smaller leaflets",
          },
          {
            scientific_name: "Rosa alternata",
            common_name: "Alternate Rose",
            confidence_score: 0.91,
            distinguishing_feature: "alternate leaflet pattern",
          },
          {
            scientific_name: "Rosa nowhere",
            common_name: "Unresolved Rose",
            confidence_score: 0.88,
            distinguishing_feature: "not in taxonomy",
          },
        ],
      });
      await insertExplorePost(client, { id: postId, userId: ownerId, scanId });
      await insertScan(client, {
        id: otherScanId,
        userId: identifierA,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        gpsLatPublic: 30.2672,
        gpsLongPublic: -97.7431,
      });
      await insertExplorePost(client, {
        id: otherPostId,
        userId: identifierA,
        scanId: otherScanId,
      });

      const taxonomy = await client.queryObject<{ id: string }>(
        `
        SELECT id
        FROM public.refresh_taxonomy_nodes_from_species_dictionary($1, TRUE)
      `,
        ["community-id-db-test"],
      );
      const taxonomyVersionId = taxonomy.rows[0].id;

      const taxonRows = await client.queryObject<SearchRow>(
        `
        SELECT taxon_id, taxonomy_version_id, scientific_name
        FROM public.search_community_taxa($1, 5, $2)
        WHERE scientific_name = 'Rosa communitatis'
      `,
        ["communitatis", taxonomyVersionId],
      );

      assertEquals(taxonRows.rows.length, 1);
      assertEquals(taxonRows.rows[0].taxonomy_version_id, taxonomyVersionId);

      const speciesTaxonId = taxonRows.rows[0].taxon_id;

      const candidateTaxonRows = await client.queryObject<SearchRow>(
        `
        SELECT taxon_id, taxonomy_version_id, scientific_name
        FROM public.search_community_taxa($1, 10, $2)
        WHERE scientific_name IN ('Rosa alternata', 'Rosa minor')
      `,
        ["rosa", taxonomyVersionId],
      );
      const candidateTaxonIdsByName = new Map(
        candidateTaxonRows.rows.map((
          row,
        ) => [row.scientific_name, row.taxon_id]),
      );

      await client.queryArray(
        `
        INSERT INTO public.explore_community_requests (
          id,
          post_id,
          scan_id,
          requested_by,
          taxonomy_version_id,
          initial_taxon_node_id
        )
        VALUES ($1, $2, $3, $4, $5, $6)
      `,
        [requestId, postId, scanId, ownerId, taxonomyVersionId, speciesTaxonId],
      );
      await client.queryArray(
        `
        INSERT INTO public.explore_community_requests (
          id,
          post_id,
          scan_id,
          requested_by,
          taxonomy_version_id,
          initial_taxon_node_id
        )
        VALUES ($1, $2, $3, $4, $5, $6)
      `,
        [
          otherRequestId,
          otherPostId,
          otherScanId,
          identifierA,
          taxonomyVersionId,
          speciesTaxonId,
        ],
      );

      await client.queryArray(
        `
        UPDATE public.explore_community_requests
        SET requested_by = $2
        WHERE id = $1
      `,
        [requestId, identifierB],
      );
      const driftedMineRows = await client.queryObject<FeedScopeRow>(
        `
        SELECT request_id, author_user_id
        FROM public.get_community_identification_feed($1, 30, NULL, NULL, NULL, NULL, 'mine')
      `,
        [ownerId],
      );
      assertEquals(driftedMineRows.rows.map((row) => row.request_id), []);

      const repairRows = await client.queryObject<RepairRow>(
        `
        SELECT public.repair_community_request_ownership_for_user($1::uuid) AS repaired_count
      `,
        [ownerId],
      );
      assertEquals(repairRows.rows[0].repaired_count, 1);

      const initialProjection = await client.queryObject<ProjectionRow>(
        `
        SELECT projection_state, public_taxon_node_id
        FROM public.explore_observation_projection
        WHERE post_id = $1
      `,
        [postId],
      );

      assertEquals(
        initialProjection.rows[0].projection_state,
        "community_needs_id",
      );
      assertEquals(initialProjection.rows[0].public_taxon_node_id, null);

      const allScopeRows = await client.queryObject<FeedScopeRow>(
        `
        SELECT request_id, author_user_id
        FROM public.get_community_identification_feed($1, 30, NULL, NULL, NULL, NULL, 'all')
      `,
        [ownerId],
      );
      const mineScopeRows = await client.queryObject<FeedScopeRow>(
        `
        SELECT request_id, author_user_id
        FROM public.get_community_identification_feed($1, 30, NULL, NULL, NULL, NULL, 'mine')
      `,
        [ownerId],
      );
      const otherMineScopeRows = await client.queryObject<FeedScopeRow>(
        `
        SELECT request_id, author_user_id
        FROM public.get_community_identification_feed($1, 30, NULL, NULL, NULL, NULL, 'mine')
      `,
        [identifierA],
      );

      assertEquals(
        allScopeRows.rows.map((row) => row.request_id).sort(),
        [requestId, otherRequestId].sort(),
      );
      assertEquals(
        mineScopeRows.rows.map((row) => row.request_id),
        [requestId],
      );
      assertEquals(mineScopeRows.rows[0].author_user_id, ownerId);
      assertEquals(
        otherMineScopeRows.rows.map((row) => row.request_id),
        [otherRequestId],
      );
      assertEquals(otherMineScopeRows.rows[0].author_user_id, identifierA);

      const detailRows = await client.queryObject<DetailRow>(
        `
        SELECT inference_tier, suggested_taxa
        FROM public.get_community_identification_detail($1, $2)
      `,
        [ownerId, requestId],
      );
      assertEquals(detailRows.rows[0].inference_tier, "pro");
      const suggestions = detailRows.rows[0].suggested_taxa;

      assertEquals(
        suggestions.map((suggestion) => suggestion.scientific_name),
        ["Rosa communitatis", "Rosa alternata", "Rosa minor"],
      );
      assertEquals(
        suggestions.map((suggestion) => suggestion.suggestion_source),
        ["ai_initial", "ai_candidate", "ai_candidate"],
      );
      assertEquals(suggestions[0].taxon_id, speciesTaxonId);
      assertEquals(suggestions[0].confidence_score, 0.97);
      assertEquals(
        suggestions[0].distinguishing_feature,
        "Visible clustered petals and leaves match the initial taxon.",
      );
      assertEquals(
        suggestions[1].taxon_id,
        candidateTaxonIdsByName.get("Rosa alternata"),
      );
      assertEquals(
        suggestions[2].taxon_id,
        candidateTaxonIdsByName.get("Rosa minor"),
      );
      assertEquals(
        suggestions[1].distinguishing_feature,
        "alternate leaflet pattern",
      );

      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierA, requestId, speciesTaxonId],
      );

      const firstOwnerNotification = await client.queryObject<{
        type: string;
        action_count: number;
        community_request_id: string | null;
      }>(
        `
        SELECT type::text, action_count, community_request_id
        FROM public.explore_post_notifications
        WHERE user_id = $1
          AND community_request_id = $2
          AND type = 'community_identification_added'
      `,
        [ownerId, requestId],
      );

      assertEquals(
        firstOwnerNotification.rows[0].type,
        "community_identification_added",
      );
      assertEquals(firstOwnerNotification.rows[0].action_count, 1);
      assertEquals(
        firstOwnerNotification.rows[0].community_request_id,
        requestId,
      );

      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierB, requestId, speciesTaxonId],
      );

      const communityNotificationRows = await client.queryObject<{
        user_id: string;
        type: string;
        action_count: number;
      }>(
        `
        SELECT user_id, type::text, action_count
        FROM public.explore_post_notifications
        WHERE community_request_id = $1
        ORDER BY type::text, user_id
      `,
        [requestId],
      );

      assertEquals(
        communityNotificationRows.rows.map((row) => [
          row.user_id,
          row.type,
          row.action_count,
        ]),
        [
          [identifierA, "community_identification_helped", 1],
          [identifierB, "community_identification_helped", 1],
          [ownerId, "community_identification_added", 2],
          [ownerId, "community_request_resolved", 1],
        ].sort((left, right) =>
          `${left[1]}-${left[0]}`.localeCompare(`${right[1]}-${right[0]}`)
        ),
      );

      const resolvedProjection = await client.queryObject<ProjectionRow>(
        `
        SELECT projection_state, public_taxon_node_id
        FROM public.explore_observation_projection
        WHERE post_id = $1
      `,
        [postId],
      );

      assertEquals(
        resolvedProjection.rows[0].projection_state,
        "community_resolved",
      );
      assertEquals(
        resolvedProjection.rows[0].public_taxon_node_id,
        speciesTaxonId,
      );

      const eventCount = await client.queryObject<{ count: bigint }>(
        `
        SELECT COUNT(*)::bigint AS count
        FROM public.community_consensus_events
        WHERE request_id = $1
      `,
        [requestId],
      );

      assertEquals(eventCount.rows[0].count > 0n, true);
    },
  );
});

Deno.test("Community ID DB - owner publish materializes GBIF-only consensus species", async () => {
  await withExploreDbTest(
    "communityIdentificationSpeciesLinking.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const identifierA = crypto.randomUUID();
      const identifierB = crypto.randomUUID();
      const initialSpeciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const requestId = crypto.randomUUID();

      await insertUser(client, ownerId, "Consensus Owner");
      await insertUser(client, identifierA, "Consensus Identifier A");
      await insertUser(client, identifierB, "Consensus Identifier B");
      await insertSpecies(client, initialSpeciesId, "Rosa provisionalis");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId: initialSpeciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        imageQualityScore: 96,
        aiConfidenceScore: 0.72,
      });
      await insertExplorePost(client, { id: postId, userId: ownerId, scanId });

      const taxonomy = await client.queryObject<{ id: string }>(
        `
        SELECT id
        FROM public.refresh_taxonomy_nodes_from_species_dictionary($1, TRUE)
      `,
        ["community-species-linking-test"],
      );
      const taxonomyVersionId = taxonomy.rows[0].id;

      const initialTaxonRows = await client.queryObject<SearchRow>(
        `
        SELECT taxon_id, taxonomy_version_id, scientific_name
        FROM public.search_community_taxa($1, 5, $2)
        WHERE scientific_name = 'Rosa provisionalis'
      `,
        ["provisionalis", taxonomyVersionId],
      );
      const initialTaxonId = initialTaxonRows.rows[0].taxon_id;

      const externalTaxonId = crypto.randomUUID();
      const gbifTaxonKey = 424242;
      await client.queryArray(
        `
        WITH genus_node AS (
          SELECT id
          FROM public.taxon_nodes
          WHERE taxonomy_version_id = $2
            AND rank = 'genus'
            AND scientific_name = 'Rosa'
          LIMIT 1
        )
        INSERT INTO public.taxon_nodes (
          id,
          taxonomy_version_id,
          path,
          parent_id,
          rank,
          scientific_name,
          common_name,
          species_id,
          gbif_taxon_key
        )
        SELECT
          $1,
          $2,
          public.community_taxon_path(
            'Plantae',
            'Tracheophyta',
            'Magnoliopsida',
            'Rosales',
            'Rosaceae',
            'Rosa',
            'Rosa externa'
          ),
          genus_node.id,
          'species',
          'Rosa externa',
          'External Rose',
          NULL,
          $3
        FROM genus_node
      `,
        [externalTaxonId, taxonomyVersionId, gbifTaxonKey],
      );

      await client.queryArray(
        `
        INSERT INTO public.explore_community_requests (
          id,
          post_id,
          scan_id,
          requested_by,
          taxonomy_version_id,
          initial_taxon_node_id
        )
        VALUES ($1, $2, $3, $4, $5, $6)
      `,
        [requestId, postId, scanId, ownerId, taxonomyVersionId, initialTaxonId],
      );

      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierA, requestId, externalTaxonId],
      );
      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierB, requestId, externalTaxonId],
      );

      const beforePublish = await client.queryObject<{
        status: string;
        resolved_taxon_node_id: string | null;
        confirmed_species_id: string | null;
        species_count: bigint;
      }>(
        `
        SELECT
          ecr.status::text,
          ecr.resolved_taxon_node_id,
          s.confirmed_species_id,
          (
            SELECT COUNT(*)::bigint
            FROM public.species_dictionary
            WHERE scientific_name = 'Rosa externa'
          ) AS species_count
        FROM public.explore_community_requests ecr
        JOIN public.scans s ON s.id = ecr.scan_id
        WHERE ecr.id = $1
      `,
        [requestId],
      );

      assertEquals(beforePublish.rows[0].status, "resolved");
      assertEquals(
        beforePublish.rows[0].resolved_taxon_node_id,
        externalTaxonId,
      );
      assertEquals(beforePublish.rows[0].confirmed_species_id, null);
      assertEquals(beforePublish.rows[0].species_count, 0n);

      const publishRows = await client.queryObject<{ species_id: string }>(
        `
        SELECT public.publish_resolved_community_request_to_explore($1, $2) AS species_id
      `,
        [postId, ownerId],
      );
      const materializedSpeciesId = publishRows.rows[0].species_id;

      const afterPublish = await client.queryObject<{
        confirmed_species_id: string | null;
        explore_published_at: Date | null;
        taxon_species_id: string | null;
        scientific_name: string;
        common_names: Record<string, string>;
        gbif_taxon_key: number | null;
        queued_count: bigint;
        job_count: bigint;
      }>(
        `
        SELECT
          s.confirmed_species_id,
          ecr.explore_published_at,
          tn.species_id AS taxon_species_id,
          sd.scientific_name,
          sd.common_names,
          sd.gbif_taxon_key,
          (
            SELECT COUNT(*)::bigint
            FROM public.species_content_provenance p
            WHERE p.species_id = sd.id
              AND p.refresh_after IS NOT NULL
              AND p.content_key IN (
                'alternative_common_names',
                'wikipedia_url',
                'wikipedia_overview',
                'habitat_description',
                'reference_images',
                'lookalikes',
                'group_tags'
              )
          ) AS queued_count,
          (
            SELECT COUNT(*)::bigint
            FROM public.species_enrichment_jobs sej
            WHERE sej.species_id = sd.id
              AND sej.content_group IN (
                'gbif_wikipedia_reference',
                'habitat',
                'lookalikes',
                'group_tags'
              )
          ) AS job_count
        FROM public.explore_community_requests ecr
        JOIN public.scans s ON s.id = ecr.scan_id
        JOIN public.taxon_nodes tn ON tn.id = ecr.resolved_taxon_node_id
        JOIN public.species_dictionary sd ON sd.id = s.confirmed_species_id
        WHERE ecr.id = $1
      `,
        [requestId],
      );

      assertEquals(
        afterPublish.rows[0].confirmed_species_id,
        materializedSpeciesId,
      );
      assertEquals(
        afterPublish.rows[0].explore_published_at instanceof Date,
        true,
      );
      assertEquals(
        afterPublish.rows[0].taxon_species_id,
        materializedSpeciesId,
      );
      assertEquals(afterPublish.rows[0].scientific_name, "Rosa externa");
      assertEquals(afterPublish.rows[0].common_names.en, "External Rose");
      assertEquals(afterPublish.rows[0].gbif_taxon_key, gbifTaxonKey);
      assertEquals(afterPublish.rows[0].queued_count, 7n);
      assertEquals(afterPublish.rows[0].job_count, 4n);
    },
  );
});

Deno.test("Community ID DB - GBIF taxonomy cache survives Dictionary sync", async () => {
  await withExploreDbTest(
    "communityIdentificationTaxonomyIndex.test",
    async (client: Client) => {
      const speciesId = crypto.randomUUID();
      await insertSpecies(client, speciesId, "Rosa indexed");

      const taxonomy = await client.queryObject<{ id: string }>(
        `
        SELECT id
        FROM public.refresh_taxonomy_nodes_from_species_dictionary($1, TRUE)
      `,
        ["community-taxonomy-index-test"],
      );
      const taxonomyVersionId = taxonomy.rows[0].id;

      await client.queryObject(
        `
        SELECT public.upsert_gbif_community_taxa($1::jsonb, $2, 10)
      `,
        [
          JSON.stringify([
            {
              gbif_taxon_key: 3000001,
              accepted_gbif_taxon_key: 3000001,
              taxonomic_status: "accepted",
              rank: "species",
              scientific_name: "Rosa externa",
              common_name: "External Rose",
              kingdom: "Plantae",
              phylum: "Tracheophyta",
              class: "Magnoliopsida",
              order: "Rosales",
              family: "Rosaceae",
              genus: "Rosa",
              species: "Rosa externa",
              kingdom_gbif_taxon_key: 6,
              genus_gbif_taxon_key: 3000000,
            },
          ]),
          "Rosa externa",
        ],
      );

      const gbifOnlyRows = await client.queryObject<{
        scientific_name: string;
        species_id: string | null;
        gbif_taxon_key: number | null;
        source: string | null;
        is_in_dictionary: boolean;
      }>(
        `
        SELECT scientific_name, species_id, gbif_taxon_key, source, is_in_dictionary
        FROM public.search_community_taxa($1, 5, $2)
        WHERE scientific_name = 'Rosa externa'
      `,
        ["externa", taxonomyVersionId],
      );

      assertEquals(gbifOnlyRows.rows.length, 1);
      assertEquals(gbifOnlyRows.rows[0].species_id, null);
      assertEquals(gbifOnlyRows.rows[0].gbif_taxon_key, 3000001);
      assertEquals(gbifOnlyRows.rows[0].source, "gbif");
      assertEquals(gbifOnlyRows.rows[0].is_in_dictionary, false);

      await client.queryObject(
        `
        SELECT public.sync_taxon_nodes_from_species_dictionary()
      `,
      );

      const afterSyncRows = await client.queryObject<{
        species_id: string | null;
      }>(
        `
        SELECT species_id
        FROM public.search_community_taxa($1, 5, $2)
        WHERE scientific_name = 'Rosa externa'
      `,
        ["externa", taxonomyVersionId],
      );

      assertEquals(afterSyncRows.rows.length, 1);
      assertEquals(afterSyncRows.rows[0].species_id, null);
    },
  );
});
