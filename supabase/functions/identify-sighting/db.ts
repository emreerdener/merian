import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { hasTierCached, setTierCache } from "../_shared/tierCache.ts";
import { CachedSpeciesRow, IdentificationCandidate } from "../identify/types.ts";

// Re-export from identify/db.ts where the logic is identical.
// upsertGhostUserIfMissing, fetchCachedSpecies, upsertSpeciesDictionary,
// fetchCandidateCommonNames, and updateGroupTags are all unchanged — they
// operate on the same tables (users, species_dictionary) regardless of whether
// identification came from an image or a text description.
export {
  upsertGhostUserIfMissing,
  fetchCachedSpecies,
  upsertSpeciesDictionary,
  fetchCandidateCommonNames,
  updateGroupTags,
} from "../identify/db.ts";

export type { CachedSpeciesRow };

// ---------------------------------------------------------------------------
// SightingScanInsertRow — mirrors ScanInsertRow from identify/db.ts with
// sighting-specific fields: no image_storage_urls (empty array) and
// is_live_capture always false.
// ---------------------------------------------------------------------------

export interface SightingScanInsertRow {
  id: string;
  user_id: string;
  species_id: string | null;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_elevation?: number | null;
  ai_confidence_score?: number;
  ecology_type?: string;
  is_invasive?: boolean;
  weather_condition?: string;
  weather_temperature_f?: number;
  semantic_location?: string;
  device_locale?: string;
  current_month?: string;
  time_of_day?: string;
  ai_reasoning?: string | null;
  extracted_visual_traits: string[];
  /** Empty for sightings — no image stored. */
  colors: string[];
  /** Empty for sightings — no R2 upload. */
  image_storage_urls: string[];
  llm_prompt_tokens?: number | null;
  llm_candidate_tokens?: number | null;
  llm_thinking_tokens?: number | null;
  llm_cached_tokens?: number | null;
  llm_total_tokens?: number | null;
  life_stage?: string;
  reproductive_condition?: string;
  individual_count?: number | null;
  ecological_interactions: string[];
  inference_tier: string;
  candidates?: IdentificationCandidate[] | null;
  /** Always null for sightings — no image to score. */
  image_quality_score?: number | null;
  /** Always false for sightings. */
  is_live_capture: false;
  /** Structured observation context staged by the user; always present for sightings. */
  user_observation_context?: Record<string, unknown> | null;
}

export async function insertSightingScan(
  row: SightingScanInsertRow,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scans")
    .upsert(row, { onConflict: "id", ignoreDuplicates: true });
  if (error) throw new Error(`insertSightingScan: ${error.message}`);
}
