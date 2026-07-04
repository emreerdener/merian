export interface MerianIdentification {
  is_biological_subject: boolean;
  is_live_capture: boolean;
  ecology_type?: "wild" | "urban" | "domesticated" | "unknown";
  scientific_name?: string;
  confidence_score: number;
  blur_score?: number;
  is_invasive?: boolean;
  invasive_status_region?: string | null;
  invasive_rationale?: string | null;
  invasive_confidence?: number | null;
  ai_reasoning: string;
  extracted_visual_traits: string[];
  common_name?: string;
  hazard_type?: "none" | "poisonous" | "venomous" | "allergenic" | "irritant";
  life_stage?:
    | "egg"
    | "larva"
    | "pupa"
    | "nymph"
    | "juvenile"
    | "subadult"
    | "adult"
    | "seedling"
    | "sapling"
    | "unknown";
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
  sex?:
    | "female"
    | "male"
    | "hermaphrodite"
    | "mixed"
    | "cannot_determine"
    | "not_applicable";
  sex_confidence?: number;
  sex_evidence?: string;
  individual_count?: number;
  ecological_interactions?: string[];
  candidates?: IdentificationCandidate[] | null;
  image_quality?: ImageQuality;
  pet_identification?: PetIdentification | null;
}

export interface IdentificationCandidate {
  scientific_name: string;
  common_name?: string;
  confidence_score: number;
  distinguishing_feature: string;
}

export interface ImageQuality {
  sharpness: number;
  framing: number;
  diagnostic_utility: number;
  overall_score: number;
}

export interface PetIdentification {
  species_group: "dog" | "cat";
  label: string;
  label_type: "breed" | "breed_mix" | "coat_pattern" | "body_type";
  confidence_score: number;
  evidence: string[];
}

export interface ObservationContextDTO {
  freeText?: string;
  free_text?: string;
  addedAt?: string;
  added_at?: string;
}

export interface Payload {
  user_id: string;
  imageBase64?: string;
  imageBase64s?: string[];
  r2ObjectKeys?: string[];
  gpsLatitude?: number | null;
  gpsLongitude?: number | null;
  gpsElevation?: number | null;
  semanticLocation?: string;
  publicLocationLabel?: string;
  geoprivacy?: string;
  weatherCondition?: string;
  weatherTemperatureF?: number;
  deviceLocale?: string;
  deviceTimeZone?: string;
  deviceRegion?: string;
  currentMonth?: number | string;
  timeOfDay?: string;
  depthScaleText?: string;
  zoomFactor?: number;
  estimatedSizeCm?: number | null;
  gps_latitude?: number | null;
  gps_longitude?: number | null;
  gps_elevation?: number | null;
  semantic_location?: string;
  public_location_label?: string;
  weather_condition?: string;
  weather_temperature_f?: number;
  device_locale?: string;
  device_time_zone?: string;
  device_region?: string;
  current_month?: number | string;
  time_of_day?: string;
  estimated_size_cm?: number | null;
  timestamp?: string;
  client_scan_id?: string;
  isIpad?: boolean;
}

export interface MultimodalPayload {
  user_id: string;
  imageBase64s?: string[];
  audioBase64s?: string[];
  audioR2ObjectKeys?: string[];
  videoR2ObjectKeys?: string[];
  videoFrameCount?: number;
  visualMediaItems?: VisualMediaItemDTO[];
  visual_media_items?: VisualMediaItemDTO[];
  audioMediaItems?: AudioMediaItemDTO[];
  audio_media_items?: AudioMediaItemDTO[];
  observation_contexts?: ObservationContextDTO[];
  r2ObjectKeys?: string[];

  // Telemetry metadata
  gpsLatitude?: number | null;
  gpsLongitude?: number | null;
  gpsElevation?: number | null;
  semanticLocation?: string;
  publicLocationLabel?: string;
  geoprivacy?: string;
  weatherCondition?: string;
  weatherTemperatureF?: number;
  deviceLocale?: string;
  deviceTimeZone?: string;
  deviceRegion?: string;
  currentMonth?: number | string;
  timeOfDay?: string;
  gps_latitude?: number | null;
  gps_longitude?: number | null;
  gps_elevation?: number | null;
  semantic_location?: string;
  public_location_label?: string;
  weather_condition?: string;
  weather_temperature_f?: number;
  device_locale?: string;
  device_time_zone?: string;
  device_region?: string;
  current_month?: number | string;
  time_of_day?: string;
  timestamp?: string;
  client_scan_id?: string;
  mimeType?: string;
  depthScaleText?: string;
  depth_scale_text?: string;
  zoomFactor?: number;
  estimatedSizeCm?: number | null;
  estimated_size_cm?: number | null;
  isIpad?: boolean;
  // Trigger TS Language Server refresh - force Deno to read the updated camelCase types
}

export interface VisualMediaItemDTO {
  kind?: "image" | "video_frame" | string;
  sourceIndex?: number;
  source_index?: number;
  clipIndex?: number;
  clip_index?: number;
  frameIndex?: number;
  frame_index?: number;
}

export interface AudioMediaItemDTO {
  kind?: "audio" | "video_audio" | string;
  sourceIndex?: number;
  source_index?: number;
  clipIndex?: number;
  clip_index?: number;
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
  /// All known English vernacular synonyms for this species beyond the primary canonical name.
  /// Sourced from GBIF vernacular names on first enrichment; served from species_dictionary cache on
  /// subsequent hits. The primary common_name is always excluded from this array.
  /// Nil on first-ever scan of a new species (enrichment hasn't completed yet).
  alternative_common_names?: string[] | null;
}

/** Row shape returned by fetchCachedSpecies — mirrors the species_dictionary SELECT columns. */
export interface CachedSpeciesRow {
  id: string;
  common_names: Record<string, string> | null;
  alternative_common_names: string[] | null;
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
  group_tags: string[] | null;
}

/** Assembled on the critical path from the cache hit/miss branches for payload construction. */
export interface StaticSpeciesData {
  taxonomy?: Record<string, string>;
  iucn_red_list_status?: string;
  hazard_type: string;
  speciesHabitat?: string;
}
