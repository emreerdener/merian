import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CachedSpeciesData, LookalikeSummary } from "./types.ts";
import { EncyclopedicData } from "../_shared/biology.ts";

export async function getCachedSpecies(
  scientificName: string,
  supabaseAdmin: SupabaseClient,
): Promise<CachedSpeciesData | null> {
  const { data: cachedSpecies, error } = await supabaseAdmin
    .from("species_dictionary")
    .select(
      "id, gbif_taxon_key, habitat_description, kingdom, phylum, class, order, family, genus, similar_species",
    )
    .eq("scientific_name", scientificName)
    .maybeSingle();

  if (error && error.code !== "PGRST116") throw error;

  return cachedSpecies as CachedSpeciesData | null;
}

/// Fetches rich lookalike entries from the species_lookalikes join table.
/// Returns an empty array if no entries exist.
export async function fetchLookalikesFromJoinTable(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<LookalikeSummary[]> {
  // Step 1: resolve lookalike IDs from the join table
  const { data: links, error: linksError } = await supabaseAdmin
    .from("species_lookalikes")
    .select("lookalike_id")
    .eq("species_id", speciesId)
    .limit(10);

  if (linksError) throw linksError;
  if (!links || links.length === 0) return [];

  const ids = (links as { lookalike_id: string }[]).map((l) => l.lookalike_id);

  // Step 2: hydrate species details for each lookalike ID
  const { data: species, error: speciesError } = await supabaseAdmin
    .from("species_dictionary")
    .select("scientific_name, common_names, reference_image_url, iucn_red_list_status")
    .in("id", ids)
    .limit(10);

  if (speciesError) throw speciesError;
  if (!species) return [];

  return (species as {
    scientific_name: string;
    common_names: Record<string, string> | null;
    reference_image_url: string | null;
    iucn_red_list_status: string | null;
  }[]).map((s) => ({
    scientific_name: s.scientific_name,
    common_name: s.common_names?.en ?? null,
    reference_image_url: s.reference_image_url,
    iucn_red_list_status: s.iucn_red_list_status,
  }));
}

/// Resolves a list of scientific name strings to species_dictionary IDs and inserts
/// bidirectional rows into species_lookalikes. Silently skips names not yet in the dictionary.
export async function resolveLookalikesToJoinTable(
  speciesId: string,
  names: string[],
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (names.length === 0) return;

  const { data: matches, error } = await supabaseAdmin
    .from("species_dictionary")
    .select("id")
    .in("scientific_name", names)
    .limit(10);

  if (error) throw error;
  if (!matches || matches.length === 0) return;

  const inserts = (matches as { id: string }[]).flatMap((m) => [
    { species_id: speciesId, lookalike_id: m.id },
    { species_id: m.id, lookalike_id: speciesId },
  ]);

  const { error: upsertError } = await supabaseAdmin
    .from("species_lookalikes")
    .upsert(inserts, { onConflict: "species_id,lookalike_id" });

  if (upsertError) throw upsertError;
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
