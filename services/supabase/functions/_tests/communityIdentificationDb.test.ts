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

type SuggestedTaxon = {
  taxon_id: string;
  scientific_name: string;
  suggestion_source: "ai_initial" | "ai_candidate";
  distinguishing_feature: string | null;
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

      const detailRows = await client.queryObject<{
        suggested_taxa: SuggestedTaxon[];
      }>(
        `
        SELECT suggested_taxa
        FROM public.get_community_identification_detail($1, $2)
      `,
        [ownerId, requestId],
      );
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

      assertEquals(firstOwnerNotification.rows[0].type, "community_identification_added");
      assertEquals(firstOwnerNotification.rows[0].action_count, 1);
      assertEquals(firstOwnerNotification.rows[0].community_request_id, requestId);

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
