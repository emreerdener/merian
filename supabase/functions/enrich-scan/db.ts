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
      "id, gbif_taxon_key, habitat_description, kingdom, phylum, class, order, family, genus, similar_species, lookalikes_flash_attempted",
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

  // Cast through unknown: the Supabase client infers the embedded join field as an array
  // internally, but PostgREST's !lookalike_id hint guarantees a single object (or null).
  return (
    data as unknown as {
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

/// Result shape for resolveLookalikesToJoinTable.
/// `lookalikes` — the summaries to serve to the client (may come from Flash directly
///   when the join table write was skipped).
/// `persisted` — true only when rows were actually written to species_lookalikes.
///   Callers MUST check this before setting lookalikes_flash_attempted, so the flag
///   is only locked once the join table contains validated data.
export interface ResolveResult {
  lookalikes: LookalikeSummary[];
  persisted: boolean;
}

/// Resolves a list of SimilarSpeciesEntry values to species_dictionary rows, inserts one-directional
/// rows into species_lookalikes (speciesId → lookalike only), and returns the resolved entries as
/// LookalikeSummary[] together with a `persisted` flag indicating whether the join table was written.
/// Silently skips entries whose scientific name is not yet in the dictionary.
/// For dictionary rows whose common_names column is NULL, back-fills the Flash-generated
/// common_name so future fetchLookalikesFromJoinTable calls return a populated common name.
/// Returning the summaries directly allows the caller to skip a redundant
/// fetchLookalikesFromJoinTable call after resolution.
///
/// @param primaryKingdom - When provided, any resolved lookalike whose kingdom differs from
///   this value is rejected before being written to the join table. Prevents cross-kingdom
///   hallucinations (e.g. plants appearing as lookalikes for insects) from persisting in cache.
export async function resolveLookalikesToJoinTable(
  speciesId: string,
  entries: SimilarSpeciesEntry[],
  supabaseAdmin: SupabaseClient,
  primaryKingdom?: string | null,
): Promise<ResolveResult> {
  if (entries.length === 0) return { lookalikes: [], persisted: false };

  // When primaryKingdom is absent we have no kingdom baseline to validate against.
  // Skip the join table write to prevent cross-kingdom entries from persisting in
  // cache — an unvalidated write here is exactly how pine cones end up as lookalikes
  // for roses. Return Flash-generated entries directly; the next call after the
  // enrichment scope populates the species' kingdom will perform the validated write.
  // persisted: false ensures lookalikes_flash_attempted is NOT set yet — the flag
  // must only lock once the join table contains validated, kingdom-checked data.
  if (!primaryKingdom) {
    return {
      lookalikes: entries.map((e) => ({
        scientific_name: e.scientific_name,
        common_name: e.common_name,
        reference_image_url: null,
        iucn_red_list_status: null,
      })),
      persisted: false,
    };
  }

  const names = entries.map((e) => e.scientific_name);
  const entryByName = new Map(entries.map((e) => [e.scientific_name, e]));

  const { data: matches, error } = await supabaseAdmin
    .from("species_dictionary")
    .select("id, scientific_name, common_names, reference_image_url, iucn_red_list_status, kingdom")
    .in("scientific_name", names)
    .limit(10);

  if (error) throw error;

  const typed = (matches ?? []) as {
    id: string;
    scientific_name: string;
    common_names: Record<string, string> | null;
    reference_image_url: string | null;
    iucn_red_list_status: string | null;
    kingdom: string | null;
  }[];

  // If none of the lookalike species are in species_dictionary yet, return the
  // Flash-generated entries directly (null referenceImageUrl/iucnRedListStatus) so
  // common names are not discarded. The client falls back to Wikipedia/iNaturalist
  // for thumbnail images when referenceImageUrl is null.
  if (typed.length === 0) {
    return {
      lookalikes: entries.map((e) => ({
        scientific_name: e.scientific_name,
        common_name: e.common_name,
        reference_image_url: null,
        iucn_red_list_status: null,
      })),
      persisted: false,
    };
  }

  // Reject any resolved species whose kingdom differs from the primary species' kingdom.
  // primaryKingdom is guaranteed non-null here — the early-exit above handles the null case.
  // Lookalikes with no kingdom on record are allowed through (can't verify, but not
  // actively contradicting).
  const validated = typed.filter((m) => {
    if (!m.kingdom) return true;
    return m.kingdom.toLowerCase() === primaryKingdom.toLowerCase();
  });

  if (validated.length === 0) {
    console.warn(
      `[resolveLookalikesToJoinTable] All ${typed.length} resolved lookalikes failed kingdom validation (expected: ${primaryKingdom}). Returning empty.`,
    );
    return { lookalikes: [], persisted: false };
  }

  // One-directional insert only: "when observing speciesId, you might confuse it for m".
  // The reverse relationship (m → speciesId) is not guaranteed to hold — a pine cone is
  // not a lookalike for a rose just because Flash once suggested the reverse. Bidirectional
  // writes caused cross-family contamination that bypassed the kingdom-only validation guard.
  const inserts = validated.map((m) => ({
    species_id: speciesId,
    lookalike_id: m.id,
  }));

  const { error: upsertError } = await supabaseAdmin
    .from("species_lookalikes")
    .upsert(inserts, { onConflict: "species_id,lookalike_id" });

  if (upsertError) throw upsertError;

  // Back-fill the English common name for any matched species that:
  //   a) Flash returned a non-null name for, AND
  //   b) the species_dictionary row has no "en" key yet
  //      (covers: common_names IS NULL, common_names = '{}', common_names = '{"fr":"..."}')
  //
  // Uses merge_common_name_en_batch (JSONB || merge) instead of N individual RPCs so all
  // back-fills complete in a single Postgres round-trip. The RPC's WHERE guard
  // (NOT (common_names ? 'en')) makes each row update a safe no-op if "en" was already
  // populated by a concurrent request, preserving existing locale keys (e.g. "fr", "de").
  const backfills = validated.filter((m) => {
    const flashName = entryByName.get(m.scientific_name)?.common_name ?? null;
    if (!flashName) return false;
    const hasEn = m.common_names != null && (m.common_names as Record<string, string>)["en"] != null;
    return !hasEn;
  });
  if (backfills.length > 0) {
    await supabaseAdmin.rpc("merge_common_name_en_batch", {
      p_updates: backfills.map((m) => ({
        id: m.id,
        en_name: entryByName.get(m.scientific_name)!.common_name,
      })),
    });
  }

  const matchedNames = new Set(validated.map((m) => m.scientific_name));

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

  return {
    lookalikes: [
      ...validated.map((m) => ({
        scientific_name: m.scientific_name,
        // Prefer the authoritative dictionary value; fall back to the Flash-generated name.
        common_name: m.common_names?.en ?? entryByName.get(m.scientific_name)?.common_name ?? null,
        reference_image_url: m.reference_image_url,
        iucn_red_list_status: m.iucn_red_list_status,
      })),
      ...unmatched,
    ],
    persisted: true,
  };
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
    const results = await Promise.allSettled(persistOps);
    for (const result of results) {
      if (result.status === "rejected") {
        console.error("[updateSpeciesEnrichment] Persist operation failed:", result.reason);
      }
    }
  }
}
