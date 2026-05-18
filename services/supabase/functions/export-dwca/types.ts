export interface DBScanRow {
  id: string;
  user_id: string;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_lat_public?: number | null;
  gps_long_public?: number | null;
  coordinate_uncertainty_in_meters?: number | string | null;
  image_storage_urls?: string[];
  life_stage?: string;
  reproductive_condition?: string;
  sex?: string | null;
  individual_count?: number | null;
  ecological_interactions?: string[];
  ai_confidence_score?: number | null;
  species_dictionary?: {
    scientific_name?: string;
    kingdom?: string;
    phylum?: string;
    class?: string;
    order?: string;
    family?: string;
    genus?: string;
    iucn_red_list_status?: string;
  };
}
