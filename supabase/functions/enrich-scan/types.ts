export interface LookalikeSummary {
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
}

export interface CachedSpeciesData {
  id: string;
  gbif_taxon_key: number | null;
  common_names: Record<string, string> | null;
  habitat_description: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  similar_species: string[] | null;
  alternative_common_names: string[] | null;
  /// True once the Flash model has been asked to generate lookalikes for this species.
  /// Prevents infinite re-calls for species whose lookalikes are genuinely obscure
  /// (all common names legitimately null). Set in index.ts after a Flash-sourced
  /// resolveLookalikesToJoinTable call completes.
  lookalikes_flash_attempted: boolean;
}
