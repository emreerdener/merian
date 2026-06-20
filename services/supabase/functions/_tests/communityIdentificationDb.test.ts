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

Deno.test("Community ID DB - versioned search, queued consensus, and projection graduation", async () => {
  await withExploreDbTest(
    "communityIdentificationDb.test",
    async (client: Client) => {
      const ownerId = crypto.randomUUID();
      const identifierA = crypto.randomUUID();
      const identifierB = crypto.randomUUID();
      const speciesId = crypto.randomUUID();
      const scanId = crypto.randomUUID();
      const postId = crypto.randomUUID();
      const requestId = crypto.randomUUID();

      await insertUser(client, ownerId, "Community Owner");
      await insertUser(client, identifierA, "Identifier A");
      await insertUser(client, identifierB, "Identifier B");
      await insertSpecies(client, speciesId, "Rosa communitatis");
      await insertScan(client, {
        id: scanId,
        userId: ownerId,
        speciesId,
        latitude: 30.2672,
        longitude: -97.7431,
        geoprivacy: "open",
        gpsLatPublic: 30.2672,
        gpsLongPublic: -97.7431,
      });
      await insertExplorePost(client, { id: postId, userId: ownerId, scanId });

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

      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierA, requestId, speciesTaxonId],
      );
      await client.queryObject(
        `
        SELECT public.submit_explore_community_identification($1, $2, $3)
      `,
        [identifierB, requestId, speciesTaxonId],
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
