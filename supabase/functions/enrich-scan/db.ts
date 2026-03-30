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

/// Fetches rich lookalike entries from the species_lookalikes join table using a single
/// embedded join — resolves both the join row and the species details in one PostgREST round-trip.
/// Returns an empty array if no entries exist.
export async function fetchLookalikesFromJoinTable(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<LookalikeSummary[]> {
  const { data, error } = await supabaseAdmin
    .from("species_lookalikes")
    .select(
      "lookalike:lookalike_id(scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId)
    .limit(10);

  if (error) throw error;
  if (!data || data.length === 0) return [];

  return (
    data as {
      lookalike: {
        scientific_name: string;
        common_names: Record<string, string> | null;
        reference_image_url: string | null;
        iucn_red_list_status: string | null;
      } | null;
    }[]
  )
    .filter((row) => row.lookalike != null)
    .map((row) => ({
      scientific_name: row.lookalike!.scientific_name,
      common_name: row.lookalike!.common_names?.en ?? null,
      reference_image_url: row.lookalike!.reference_image_url,
      iucn_red_list_status: row.lookalike!.iucn_red_list_status,
    }));
}

/// Resolves a list of scientific name strings to species_dictionary rows, inserts bidirectional
/// rows into species_lookalikes, and returns the resolved entries as LookalikeSummary[].
/// Silently skips names not yet in the dictionary. Returning the summaries directly allows the
/// caller to skip a redundant fetchLookalikesFromJoinTable call after resolution.
export async function resolveLookalikesToJoinTable(
  speciesId: string,
  names: string[],
  supabaseAdmin: SupabaseClient,
): Promise<LookalikeSummary[]> {
  if (names.length === 0) return [];

  const { data: matches, error } = await supabaseAdmin
    .from("species_dictionary")
    .select("id, scientific_name, common_names, reference_image_url, iucn_red_list_status")
    .in("scientific_name", names)
    .limit(10);

  if (error) throw error;
  if (!matches || matches.length === 0) return [];

  const typed = matches as {
    id: string;
    scientific_name: string;
    common_names: Record<string, string> | null;
    reference_image_url: string | null;
    iucn_red_list_status: string | null;
  }[];

  const inserts = typed.flatMap((m) => [
    { species_id: speciesId, lookalike_id: m.id },
    { species_id: m.id, lookalike_id: speciesId },
  ]);

  const { error: upsertError } = await supabaseAdmin
    .from("species_lookalikes")
    .upsert(inserts, { onConflict: "species_id,lookalike_id" });

  if (upsertError) throw upsertError;

  return typed.map((m) => ({
    scientific_name: m.scientific_name,
    common_name: m.common_names?.en ?? null,
    reference_image_url: m.reference_image_url,
    iucn_red_list_status: m.iucn_red_list_status,
  }));
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
