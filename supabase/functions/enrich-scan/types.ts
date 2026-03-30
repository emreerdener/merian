export interface LookalikeSummary {
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
}

export interface CachedSpeciesData {
  id: string;
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
