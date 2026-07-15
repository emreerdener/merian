import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CachedSpeciesRow,
  IdentificationCandidate,
  PetIdentification,
} from "../_shared/identify/types.ts";

// Re-export from identify/db.ts where the logic is identical.
// upsertGhostUserIfMissing, fetchCachedSpecies, upsertSpeciesDictionary,
// fetchCandidateCommonNames, and updateGroupTags are all unchanged — they
// operate on the same tables (users, species_dictionary) regardless of whether
// identification came from an image or a text description.
export {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  mergeSpeciesCommonNames,
  resolveScanGeoprivacy,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "../_shared/identify/db.ts";
import { resolveScanGeoprivacy } from "../_shared/identify/db.ts";

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
  geoprivacy?: string | null;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_elevation?: number | null;
  ai_confidence_score?: number;
  is_biological_subject: boolean;
  ecology_type?: string;
  is_invasive?: boolean;
  invasive_status_region?: string | null;
  invasive_rationale?: string | null;
  invasive_confidence?: number | null;
  weather_condition?: string;
  weather_temperature_f?: number;
  semantic_location?: string;
  public_location_label?: string | null;
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
  sex?: string | null;
  sex_confidence?: number | null;
  sex_evidence?: string | null;
  individual_count?: number | null;
  ecological_interactions: string[];
  inference_tier: string;
  candidates?: IdentificationCandidate[] | null;
  pet_identification?: PetIdentification | null;
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
  const geoprivacy = await resolveScanGeoprivacy(
    row.user_id,
    supabaseAdmin,
    row.geoprivacy,
  );
  const scanRow = {
    ...row,
    geoprivacy,
    public_location_label: geoprivacy === "private"
      ? null
      : row.public_location_label,
  };

  const { error } = await supabaseAdmin
    .from("scans")
    .upsert(scanRow, {
      onConflict: "id",
      ignoreDuplicates: true,
    });
  if (error) throw new Error(`insertDescribeScan: ${error.message}`);
}
