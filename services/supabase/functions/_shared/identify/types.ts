import type {
  ClientPayload as ContractClientPayload,
  MerianIdentification as ContractMerianIdentification,
} from "./contract.ts";

export type MerianIdentification = ContractMerianIdentification;
export type ClientPayload = ContractClientPayload;
export type IdentificationCandidate = NonNullable<
  MerianIdentification["candidates"]
>[number];
export type ImageQuality = NonNullable<
  MerianIdentification["image_quality"]
>;
export type PetIdentification = NonNullable<
  MerianIdentification["pet_identification"]
>;

export interface ObservationContextDTO {
  freeText?: string;
  free_text?: string;
  addedAt?: string;
  added_at?: string;
}

export interface PreferredFieldTripGoalDTO {
  user_field_trip_id?: string;
  item_id?: string;
  userFieldTripId?: string;
  itemId?: string;
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
  preferred_goal?: PreferredFieldTripGoalDTO;
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
  preferred_goal?: PreferredFieldTripGoalDTO;
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
  focusRegion?: NormalizedImageFocusRegionDTO;
  focus_region?: NormalizedImageFocusRegionDTO;
}

export interface NormalizedImageFocusRegionDTO {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  source?: "vision_objectness" | string;
}

export interface AudioMediaItemDTO {
  kind?: "audio" | "video_audio" | string;
  sourceIndex?: number;
  source_index?: number;
  clipIndex?: number;
  clip_index?: number;
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
