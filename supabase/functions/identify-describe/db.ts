import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { hasTierCached, setTierCache } from "../_shared/tierCache.ts";
import {
  CachedSpeciesRow,
  IdentificationCandidate,
} from "../_shared/identify/types.ts";

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
} from "../_shared/identify/db.ts";

export type { CachedSpeciesRow };

// ---------------------------------------------------------------------------
// DescribeScanInsertRow — mirrors ScanInsertRow from identify/db.ts with
// describe-specific fields: no image_storage_urls (empty array) and
// is_live_capture always false.
// ---------------------------------------------------------------------------

export interface DescribeScanInsertRow {
  id: string;
  user_id: string;
  species_id: string | null;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_elevation?: number | null;
  ai_confidence_score?: number;
  is_biological_subject: boolean;
  ecology_type?: string;
  is_invasive?: boolean;
  weather_condition?: string;
  weather_temperature_f?: number;
  semantic_location?: string;
  device_locale?: string;
  device_time_zone?: string;
  current_month?: number | null;
  time_of_day?: string;
  ai_reasoning?: string | null;
  extracted_visual_traits: string[];
  /** Empty for describes — no image stored. */
  colors: string[];
  /** Empty for describes — no R2 upload. */
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
  /** Always null for describes — no image to score. */
  image_quality_score?: number | null;
  /** Always false for describes. */
  is_live_capture: false;
  /** Structured observation context staged by the user; always present for describes. */
  user_observation_context?: Record<string, unknown> | null;
}

export async function insertDescribeScan(
  row: DescribeScanInsertRow,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scans")
    .upsert(row, { onConflict: "id", ignoreDuplicates: true });
  if (error) throw new Error(`insertDescribeScan: ${error.message}`);
}
