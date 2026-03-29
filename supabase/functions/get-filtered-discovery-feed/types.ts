export interface SpeciesDictionary {
  id?: string;
  scientific_name?: string;
  common_names?: string[];
  wikipedia_url?: string;
  reference_image_url?: string;
  iucn_red_list_status?: string;
  hazard_type?: string;
  kingdom?: string;
}

export interface FeedScan {
  id?: string;
  user_id?: string;
  timestamp?: string;
  image_storage_urls?: string[];
  gps_lat_exact?: number;
  gps_long_exact?: number;
  gps_lat_public?: number;
  gps_long_public?: number;
  ecology_type?: string;
  is_invasive?: boolean;
  is_live_capture?: boolean;
  colors?: string[];
  semantic_location?: string;
  weather_condition?: string;
  weather_temperature_f?: number;
  ai_confidence_score?: number;
  species_dictionary?: SpeciesDictionary;
  users?: { is_shadowbanned: boolean } | { is_shadowbanned: boolean }[];
  [key: string]: unknown;
}
