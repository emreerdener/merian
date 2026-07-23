import { SupabaseClient } from "@supabase/supabase-js";
import {
  buildGroupTagsProvenanceRows,
  buildSpeciesDictionaryProvenanceRows,
  recordSpeciesContentProvenance,
} from "../_shared/speciesContentProvenance.ts";
import { resolveScanGeoprivacy } from "../_shared/identify/db.ts";
import { AudioCandidate } from "./types.ts";

// MARK: - User

export async function upsertGhostUserIfMissing(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("users")
    .upsert(
      { id: userId, subscription_tier: "free" },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) {
    throw new Error(
      `Failed to ensure audio scan user exists: ${error.message}`,
    );
  }
}

// MARK: - Species Dictionary

const SPECIES_SELECT =
  "id, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags";

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

export async function fetchCachedSpecies(
  scientificName: string,
  supabaseAdmin: SupabaseClient,
): Promise<CachedSpeciesRow | null> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary")
    .select(SPECIES_SELECT)
    .eq("scientific_name", scientificName)
    .maybeSingle();
  if (error) throw new Error(`fetchCachedSpecies: ${error.message}`);
  return data as CachedSpeciesRow | null;
}

export interface SpeciesUpsertData {
  scientific_name: string;
  common_names: Record<string, string | undefined>;
  alternative_common_names?: string[] | null;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  wikipedia_overview?: string | null;
  hazard_type?: string;
  native_region: string;
  iucn_red_list_status?: string;
  habitat_description?: string;
  wikipedia_url?: string | null;
  gbif_taxon_key?: number | null;
  reference_image_url?: string | null;
}

export async function upsertSpeciesDictionary(
  data: SpeciesUpsertData,
  supabaseAdmin: SupabaseClient,
): Promise<string | null> {
  const { data: row, error } = await supabaseAdmin
    .from("species_dictionary")
    .upsert(data, { onConflict: "scientific_name", ignoreDuplicates: false })
    .select("id")
    .maybeSingle();
  if (error) throw new Error(`upsertSpeciesDictionary: ${error.message}`);

  const speciesId = typeof row?.id === "string" ? row.id : null;
  if (speciesId) {
    await recordSpeciesContentProvenance(
      supabaseAdmin,
      buildSpeciesDictionaryProvenanceRows(speciesId, data),
      "audio-spec/upsertSpeciesDictionary",
    );
  }

  return speciesId;
}

export async function updateGroupTags(
  scientificName: string,
  groupTags: string[],
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary")
    .update({ group_tags: groupTags })
    .eq("scientific_name", scientificName)
    .select("id")
    .maybeSingle();
  if (error) throw new Error(`updateGroupTags: ${error.message}`);

  const speciesId = typeof data?.id === "string" ? data.id : null;
  if (speciesId) {
    await recordSpeciesContentProvenance(
      supabaseAdmin,
      buildGroupTagsProvenanceRows(speciesId, groupTags),
      "audio-spec/updateGroupTags",
    );
  }
}

// MARK: - Scans

export interface AudioScanInsertRow {
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
  blur_score: null;
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
  colors: string[];
  llm_prompt_tokens?: number | null;
  llm_candidate_tokens?: number | null;
  llm_thinking_tokens?: number | null;
  llm_cached_tokens?: number | null;
  llm_total_tokens?: number | null;
  llm_usage_metadata?: Record<string, unknown>;
  image_storage_urls: string[];
  life_stage: string;
  reproductive_condition: string;
  sex?: string | null;
  sex_confidence?: number | null;
  sex_evidence?: string | null;
  individual_count: null;
  ecological_interactions: string[];
  estimated_size_cm: null;
  inference_tier: string;
  candidates?: AudioCandidate[] | null;
  image_quality_score: null;
  is_live_capture: boolean;
}

/**
 * Upsert with ignoreDuplicates so a client-provided scan ID makes this idempotent.
 * Mirrors the pattern in identify/db.ts to keep retry semantics consistent.
 */
export async function insertScan(
  row: AudioScanInsertRow,
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
  if (error) throw new Error(`insertScan: ${error.message}`);
}
