export interface MerianIdentification {
  is_biological_subject: boolean;
  is_live_capture: boolean;
  ecology_type?: "wild" | "urban" | "domesticated" | "unknown";
  scientific_name?: string;
  confidence_score: number;
  blur_score: number;
  is_invasive?: boolean;
  ai_reasoning: string;
  extracted_visual_traits: string[];
  colors?: string[];
  common_name?: string;
  hazard_type?: "none" | "poisonous" | "venomous" | "allergenic" | "irritant";
  life_stage?: "egg" | "larva" | "pupa" | "nymph" | "juvenile" | "subadult" | "adult" | "seedling" | "sapling" | "unknown";
  reproductive_condition?:
    | "flowering"
    | "fruiting"
    | "budding"
    | "vegetative"
    | "sporing"
    | "pregnant"
    | "gravid"
    | "mating"
    | "spawning"
    | "nesting"
    | "dormant"
    | "not_applicable";
  individual_count?: number;
  ecological_interactions?: string[];
  candidates?: IdentificationCandidate[] | null;
}

/** A single alternative species the model considered when confidence was below threshold. */
export interface IdentificationCandidate {
  scientific_name: string;
  confidence_score: number;
}

export interface ClientPayload extends MerianIdentification {
  scan_id: string;
  reference_image_url?: string | null;
  wikipedia_url?: string | null;
  wikipedia_overview?: string | null;
  group_tags?: string[] | null;
  gbif_taxon_key?: number | null;
  taxonomy?: Record<string, string>;
  iucn_red_list_status?: string;
  insight_data?: {
    ai_reasoning: string;
    hazard_type: string;
  };
  species_insights?: {
    habitat_description: string;
  };
  inference_tier: string;
}

/** Row shape returned by fetchCachedSpecies — mirrors the species_dictionary SELECT columns. */
export interface CachedSpeciesRow {
  id: string;
  common_names: Record<string, string> | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  wikipedia_overview: string | null;
  hazard_type: string | null;
  reference_image_url: string | null;
  wikipedia_url: string | null;
  iucn_red_list_status: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  similar_species: string[] | null;
  group_tags: string[] | null;
}

/** Assembled on the critical path from the cache hit/miss branches for payload construction. */
export interface StaticSpeciesData {
  taxonomy?: Record<string, string>;
  iucn_red_list_status?: string;
  hazard_type: string;
  speciesHabitat?: string;
}
