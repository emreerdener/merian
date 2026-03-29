import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CachedSpeciesData } from "./types.ts";
import { EncyclopedicData } from "../_shared/biology.ts";

export async function getCachedSpecies(
  scientificName: string,
  supabaseAdmin: SupabaseClient,
): Promise<CachedSpeciesData | null> {
  const { data: cachedSpecies, error } = await supabaseAdmin
    .from("species_dictionary")
    .select(
      "gbif_taxon_key, habitat_description, kingdom, phylum, class, order, family, genus, similar_species",
    )
    .eq("scientific_name", scientificName)
    .maybeSingle();

  if (error && error.code !== "PGRST116") throw error;

  return cachedSpecies as CachedSpeciesData | null;
}

export async function updateSpeciesEnrichment(
  scientificName: string,
  enrichmentResult: EncyclopedicData | null,
  similarResult: { similar_species: string[] } | null,
  supabaseAdmin: SupabaseClient,
) {
  const persistOps: PromiseLike<unknown>[] = [];

  if (enrichmentResult) {
    persistOps.push(
      supabaseAdmin
        .from("species_dictionary")
        .update({
          habitat_description: enrichmentResult.habitat_description,
          kingdom: enrichmentResult.taxonomy.kingdom,
          phylum: enrichmentResult.taxonomy.phylum,
          class: enrichmentResult.taxonomy.class,
          order: enrichmentResult.taxonomy.order,
          family: enrichmentResult.taxonomy.family,
          genus: enrichmentResult.taxonomy.genus,
        })
        .eq("scientific_name", scientificName),
    );
  }

  if (similarResult) {
    persistOps.push(
      supabaseAdmin
        .from("species_dictionary")
        .update({
          similar_species: similarResult.similar_species,
        })
        .eq("scientific_name", scientificName),
    );
  }

  if (persistOps.length > 0) {
    await Promise.allSettled(persistOps);
  }
}
