import type { SupabaseClient } from "@supabase/supabase-js";
import type { CachedSpeciesRow } from "./types.ts";

export interface IdentificationDictionaryHydration {
  cachedSpecies: CachedSpeciesRow | null;
  candidateCommonNames: Map<string, string>;
}

export async function fetchIdentificationDictionaryHydration(
  primaryScientificName: string | null,
  candidateScientificNames: string[],
  supabaseAdmin: SupabaseClient,
): Promise<IdentificationDictionaryHydration> {
  const { data, error } = await supabaseAdmin.rpc(
    "hydrate_identification_dictionary",
    {
      p_primary_scientific_name: primaryScientificName,
      p_candidate_scientific_names: candidateScientificNames,
    },
  );
  if (error) {
    throw new Error(`fetchIdentificationDictionaryHydration: ${error.message}`);
  }

  const hydration = data as {
    primary?: CachedSpeciesRow | null;
    candidate_common_names?: Record<string, unknown> | null;
  } | null;
  const candidateCommonNames = new Map<string, string>();
  for (
    const [scientificName, commonName] of Object.entries(
      hydration?.candidate_common_names ?? {},
    )
  ) {
    if (typeof commonName === "string" && commonName.trim().length > 0) {
      candidateCommonNames.set(scientificName, commonName.trim());
    }
  }

  return {
    cachedSpecies: hydration?.primary ?? null,
    candidateCommonNames,
  };
}
