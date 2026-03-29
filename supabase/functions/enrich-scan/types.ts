export interface CachedSpeciesData {
  gbif_taxon_key: number | null;
  habitat_description: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  similar_species: string[] | null;
}
