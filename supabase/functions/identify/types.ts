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
