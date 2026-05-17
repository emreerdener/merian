import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { PublicSimilarSpecies } from "../_shared/publicSpeciesProjection.ts";

export interface ExplorePostDetailRow {
  post_id: string;
  field_notes?: string | null;
  species_dictionary_id?: string | null;
  alternative_common_names?: string[] | null;
  taxonomy_kingdom?: string | null;
  taxonomy_phylum?: string | null;
  taxonomy_class?: string | null;
  taxonomy_order?: string | null;
  taxonomy_family?: string | null;
  taxonomy_genus?: string | null;
  ai_reasoning?: string | null;
  habitat_description?: string | null;
  gbif_taxon_key?: number | null;
  iucn_red_list_status?: string | null;
  wikipedia_url?: string | null;
  reference_image_url?: string | null;
  wikipedia_overview?: string | null;
  similar_species?: ExplorePostDetailSimilarSpecies[] | null;
}

export type ExplorePostDetailSimilarSpecies = PublicSimilarSpecies;

export async function fetchExplorePostDetail(
  userId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostDetailRow | null> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_post_detail", {
    self_id: userId,
    target_post_id: postId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore post detail: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostDetailRow[];
  return rows[0] ?? null;
}
