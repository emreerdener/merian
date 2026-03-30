import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CachedSpeciesData, LookalikeSummary } from "./types.ts";
import { EncyclopedicData, SimilarSpeciesEntry } from "../_shared/biology.ts";

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
  // Use explicit table!column hint to disambiguate the two FKs (species_id and lookalike_id)
  // that both point to species_dictionary. Without the hint PostgREST cannot determine which
  // FK to follow and returns an ambiguous-relationship error.
  const { data, error } = await supabaseAdmin
    .from("species_lookalikes")
    .select(
      "lookalike:species_dictionary!lookalike_id(scientific_name, common_names, reference_image_url, iucn_red_list_status)",
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

/// Resolves a list of SimilarSpeciesEntry values to species_dictionary rows, inserts bidirectional
/// rows into species_lookalikes, and returns the resolved entries as LookalikeSummary[].
/// Silently skips entries whose scientific name is not yet in the dictionary.
/// For dictionary rows whose common_names column is NULL, back-fills the Flash-generated
/// common_name so future fetchLookalikesFromJoinTable calls return a populated common name.
/// Returning the summaries directly allows the caller to skip a redundant
/// fetchLookalikesFromJoinTable call after resolution.
export async function resolveLookalikesToJoinTable(
  speciesId: string,
  entries: SimilarSpeciesEntry[],
  supabaseAdmin: SupabaseClient,
): Promise<LookalikeSummary[]> {
  if (entries.length === 0) return [];

  const names = entries.map((e) => e.scientific_name);
  const entryByName = new Map(entries.map((e) => [e.scientific_name, e]));

  const { data: matches, error } = await supabaseAdmin
    .from("species_dictionary")
    .select("id, scientific_name, common_names, reference_image_url, iucn_red_list_status")
    .in("scientific_name", names)
    .limit(10);

  if (error) throw error;

  const typed = (matches ?? []) as {
    id: string;
    scientific_name: string;
    common_names: Record<string, string> | null;
    reference_image_url: string | null;
    iucn_red_list_status: string | null;
  }[];

  // If none of the lookalike species are in species_dictionary yet, return the
  // Flash-generated entries directly (null referenceImageUrl/iucnRedListStatus) so
  // common names are not discarded. The client falls back to Wikipedia/iNaturalist
  // for thumbnail images when referenceImageUrl is null.
  if (typed.length === 0) {
    return entries.map((e) => ({
      scientific_name: e.scientific_name,
      common_name: e.common_name,
      reference_image_url: null,
      iucn_red_list_status: null,
    }));
  }

  const inserts = typed.flatMap((m) => [
    { species_id: speciesId, lookalike_id: m.id },
    { species_id: m.id, lookalike_id: speciesId },
  ]);

  const { error: upsertError } = await supabaseAdmin
    .from("species_lookalikes")
    .upsert(inserts, { onConflict: "species_id,lookalike_id" });

  if (upsertError) throw upsertError;

  // Back-fill common_names for species whose entire common_names column is NULL.
  // Only fires when the Flash model returned a non-empty name and the DB column is
  // fully absent (not merely missing the "en" key) — avoids overwriting partial locale data.
  const backfills = typed.filter(
    (m) => m.common_names === null && (entryByName.get(m.scientific_name)?.common_name ?? null) !== null,
  );
  if (backfills.length > 0) {
    await Promise.allSettled(
      backfills.map((m) =>
        supabaseAdmin
          .from("species_dictionary")
          .update({ common_names: { en: entryByName.get(m.scientific_name)!.common_name } })
          .eq("id", m.id)
          .is("common_names", null),
      ),
    );
  }

  const matchedNames = new Set(typed.map((m) => m.scientific_name));

  // Append any Flash-generated entries for species not yet in species_dictionary.
  // These carry common_name from Flash but no reference image or IUCN data — the
  // client falls back to Wikipedia/iNaturalist for thumbnails when referenceImageUrl is null.
  const unmatched: LookalikeSummary[] = entries
    .filter((e) => !matchedNames.has(e.scientific_name))
    .map((e) => ({
      scientific_name: e.scientific_name,
      common_name: e.common_name,
      reference_image_url: null,
      iucn_red_list_status: null,
    }));

  return [
    ...typed.map((m) => ({
      scientific_name: m.scientific_name,
      // Prefer the authoritative dictionary value; fall back to the Flash-generated name.
      common_name: m.common_names?.en ?? entryByName.get(m.scientific_name)?.common_name ?? null,
      reference_image_url: m.reference_image_url,
      iucn_red_list_status: m.iucn_red_list_status,
    })),
    ...unmatched,
  ];
}

export async function updateSpeciesEnrichment(
  scientificName: string,
  enrichmentResult: EncyclopedicData | null,
  similarResult: { similar_species: SimilarSpeciesEntry[] } | null,
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
    // Persist scientific names only into the TEXT[] column for backwards compatibility.
    persistOps.push(
      supabaseAdmin
        .from("species_dictionary")
        .update({
          similar_species: similarResult.similar_species.map((e) => e.scientific_name),
        })
        .eq("scientific_name", scientificName),
    );
  }

  if (persistOps.length > 0) {
    await Promise.allSettled(persistOps);
  }
}
