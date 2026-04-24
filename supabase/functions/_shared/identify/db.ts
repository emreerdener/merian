import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { hasTierCached, setTierCache } from "../tierCache.ts";
import { CachedSpeciesRow, IdentificationCandidate } from "./types.ts";

export async function upsertGhostUserIfMissing(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  if (!hasTierCached(userId)) {
    const { data: existingUser } = await supabaseAdmin
      .from("users")
      .select("subscription_tier")
      .eq("id", userId)
      .maybeSingle();
    if (existingUser) {
      setTierCache(userId, existingUser.subscription_tier as string);
    } else {
      await supabaseAdmin
        .from("users")
        .upsert(
          { id: userId, subscription_tier: "free" },
          { onConflict: "id", ignoreDuplicates: true },
        );
      setTierCache(userId, "free");
    }
  }
}

const SPECIES_SELECT =
  "id, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags";

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
  return row?.id ?? null;
}

export async function updateGroupTags(
  scientificName: string,
  groupTags: string[],
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("species_dictionary")
    .update({ group_tags: groupTags })
    .eq("scientific_name", scientificName);
  if (error) throw new Error(`updateGroupTags: ${error.message}`);
}

export interface ScanInsertRow {
  id: string;
  user_id: string;
  species_id: string | null;
  timestamp?: string;
  gps_lat_exact?: number | null;
  gps_long_exact?: number | null;
  gps_elevation?: number | null;
  ai_confidence_score?: number;
  blur_score?: number;
  ecology_type?: string;
  is_invasive?: boolean;
  weather_condition?: string;
  weather_temperature_f?: number;
  semantic_location?: string;
  device_locale?: string;
  current_month?: number | null;
  time_of_day?: string;
  depth_scale_text?: string;
  ai_reasoning?: string | null;
  extracted_visual_traits: string[];
  colors: string[];
  llm_prompt_tokens?: number | null;
  llm_candidate_tokens?: number | null;
  llm_thinking_tokens?: number | null;
  llm_cached_tokens?: number | null;
  llm_total_tokens?: number | null;
  image_storage_urls: string[];
  life_stage?: string;
  reproductive_condition?: string;
  individual_count?: number | null;
  ecological_interactions: string[];
  estimated_size_cm?: number | null;
  inference_tier: string;
  candidates?: IdentificationCandidate[] | null;
  image_quality_score?: number | null;
  is_live_capture?: boolean;
  /** Structured observation context staged by the user; NULL for image-only scans. */
  user_observation_context?: Record<string, unknown> | null;
}

export async function fetchCandidateCommonNames(
  scientificNames: string[],
  supabaseAdmin: SupabaseClient,
): Promise<Map<string, string>> {
  if (scientificNames.length === 0) return new Map();
  const { data, error } = await supabaseAdmin
    .from("species_dictionary")
    .select("scientific_name, common_names")
    .in("scientific_name", scientificNames);
  if (error) return new Map();
  const result = new Map<string, string>();
  for (const row of data ?? []) {
    const en = (row.common_names as Record<string, string> | null)?.en;
    if (en) result.set(row.scientific_name as string, en);
  }
  return result;
}

export async function insertScan(
  row: ScanInsertRow,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scans")
    .upsert(row, { onConflict: "id", ignoreDuplicates: true });
  if (error) throw new Error(`insertScan: ${error.message}`);
}
