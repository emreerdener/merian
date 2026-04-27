import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExplorePostDetailRow {
  post_id: string;
  species_dictionary_id?: string | null;
  taxonomy_kingdom?: string | null;
  taxonomy_phylum?: string | null;
  taxonomy_class?: string | null;
  taxonomy_order?: string | null;
  taxonomy_family?: string | null;
  taxonomy_genus?: string | null;
  habitat_description?: string | null;
  gbif_taxon_key?: number | null;
  iucn_red_list_status?: string | null;
  wikipedia_overview?: string | null;
}

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
