// MARK: - Request

/** Payload sent by the iOS client for bioacoustic identification. */
export interface AudioClientRequest {
  user_id: string;
  /** R2 staging key for the recorded WAV file, e.g. "staging/{userId}/uuid.wav". Mutually exclusive with audio_base64. */
  audio_r2_key?: string;
  /** Base64-encoded WAV sent inline (iOS live path). Mutually exclusive with audio_r2_key. */
  audio_base64?: string;
  /** Client-generated UUID for idempotent scan upserts. */
  client_scan_id?: string;
  // Telemetry — mirrors CaptureTelemetry fields in the iOS client.
  timestamp?: string;
  gps_latitude?: number | null;
  gps_longitude?: number | null;
  gps_elevation?: number | null;
  semantic_location?: string | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  device_locale?: string | null;
  device_time_zone?: string | null;
  device_region?: string | null;
  current_month?: string | null;
  time_of_day?: string | null;
}

// MARK: - Gemini bioacoustic response

/** Structured JSON returned by Gemini for an audio recording. */
export interface AudioIdentification {
  is_biological_subject: boolean;
  scientific_name?: string;
  common_name?: string;
  confidence_score: number;
  ai_reasoning: string;
  ecology_type?: "wild" | "urban" | "domesticated" | "unknown";
  is_invasive?: boolean;
  candidates?: AudioCandidate[] | null;
}

export interface AudioCandidate {
  scientific_name: string;
  confidence_score: number;
  distinguishing_feature: string;
}

// MARK: - Response

/**
 * Payload returned to the iOS client.
 * Field names MUST match the Swift `EdgeResponse` struct in InferenceEdgeDTOs.swift
 * so the existing decoder can parse audio-spec responses without changes.
 */
export interface AudioClientPayload {
  scan_id: string;
  is_biological_subject: boolean;
  is_live_capture: boolean;
  scientific_name?: string;
  common_name?: string;
  confidence_score: number;
  ecology_type?: string;
  is_invasive?: boolean;
  life_stage?: string;
  inference_tier: string;
  taxonomy?: Record<string, string>;
  iucn_red_list_status?: string;
  reference_image_url?: string | null;
  wikipedia_url?: string | null;
  wikipedia_overview?: string | null;
  group_tags?: string[] | null;
  gbif_taxon_key?: number | null;
  alternative_common_names?: string[] | null;
  insight_data?: {
    ai_reasoning: string;
    hazard_type: string;
  };
  species_insights?: {
    habitat_description: string;
  };
  candidates?: AudioCandidate[] | null;
}
