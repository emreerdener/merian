import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  fetchGbifCommunityTaxa,
  type GbifCommunityTaxon,
  shouldFetchGbifCommunityTaxa,
} from "./gbif.ts";

export interface CommunityTaxonSearchRow {
  taxon_id: string;
  taxonomy_version_id: string;
  common_name: string | null;
  scientific_name: string;
  rank: string;
  path: string;
  species_id: string | null;
  gbif_taxon_key?: number | null;
  source?: string | null;
  is_in_dictionary?: boolean | null;
  accepted_gbif_taxon_key?: number | null;
  taxonomic_status?: string | null;
}

export type GbifCommunityTaxaFetcher = (
  query: string,
  limit: number,
) => Promise<GbifCommunityTaxon[]>;

export async function searchCommunityTaxa(
  query: string,
  limit: number,
  taxonomyVersionId: string | null,
  supabaseAdmin: SupabaseClient,
  gbifFetcher: GbifCommunityTaxaFetcher = fetchGbifCommunityTaxa,
): Promise<CommunityTaxonSearchRow[]> {
  const localRows = await rpcSearchCommunityTaxa(
    query,
    limit,
    taxonomyVersionId,
    supabaseAdmin,
  );

  if (!shouldFetchGbifCommunityTaxa(query, localRows.length, limit)) {
    return localRows;
  }

  try {
    const gbifTaxa = await gbifFetcher(query, limit);
    if (gbifTaxa.length === 0) return localRows;

    const { error } = await supabaseAdmin.rpc(
      "upsert_gbif_community_taxa",
      {
        taxa: gbifTaxa,
        query_text: query,
        max_rows: limit,
      },
    );
    if (error) {
      console.warn(
        `[search-community-taxa] GBIF cache insert failed: ${error.message}`,
      );
      return localRows;
    }

    return await rpcSearchCommunityTaxa(
      query,
      limit,
      taxonomyVersionId,
      supabaseAdmin,
    );
  } catch (error) {
    console.warn(
      `[search-community-taxa] GBIF fallback failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return localRows;
  }
}

async function rpcSearchCommunityTaxa(
  query: string,
  limit: number,
  taxonomyVersionId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<CommunityTaxonSearchRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "search_community_taxa",
    {
      query_text: query,
      max_limit: limit,
      target_taxonomy_version_id: taxonomyVersionId,
    },
  );

  if (error) {
    throw new Error(`Failed to search community taxa: ${error.message}`);
  }

  return (data ?? []) as CommunityTaxonSearchRow[];
}
