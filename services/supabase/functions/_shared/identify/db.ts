import { SupabaseClient } from "@supabase/supabase-js";
import {
  legacyReferenceImageUrls,
  type PublicReferenceImageSource,
  referenceImageSource,
} from "../publicSpeciesProjection.ts";
import {
  buildGroupTagsProvenanceRows,
  buildSpeciesDictionaryProvenanceRows,
  recordSpeciesContentProvenance,
} from "../speciesContentProvenance.ts";
import {
  getCachedTierResolution,
  hasTierCached,
  resolutionForUserRow,
  setTierResolutionCache,
} from "../tierCache.ts";
import {
  CachedSpeciesRow,
  IdentificationCandidate,
  PetIdentification,
} from "./types.ts";

export type ScanGeoprivacy = "open" | "obscured" | "private";
export type ScanEcologyType = "wild" | "urban" | "domesticated" | "unknown";

const VALID_SCAN_GEOPRIVACY = new Set<ScanGeoprivacy>([
  "open",
  "obscured",
  "private",
]);
const VALID_SCAN_ECOLOGY_TYPES = new Set<ScanEcologyType>([
  "wild",
  "urban",
  "domesticated",
  "unknown",
]);

export function isScanGeoprivacy(value: unknown): value is ScanGeoprivacy {
  return typeof value === "string" &&
    VALID_SCAN_GEOPRIVACY.has(value as ScanGeoprivacy);
}

export function normalizeScanEcologyType(value: unknown): ScanEcologyType {
  return typeof value === "string" &&
      VALID_SCAN_ECOLOGY_TYPES.has(value as ScanEcologyType)
    ? value as ScanEcologyType
    : "unknown";
}

export function mergeSpeciesCommonNames(
  existingCommonNames: Record<string, string | undefined> | null | undefined,
  scanCommonName: string | null | undefined,
): Record<string, string | undefined> {
  const merged = { ...(existingCommonNames ?? {}) };
  const existingEnglishName = merged.en?.trim();
  if (existingEnglishName) {
    merged.en = existingEnglishName;
    return merged;
  }

  const normalizedScanCommonName = scanCommonName?.trim();
  if (normalizedScanCommonName) {
    merged.en = normalizedScanCommonName;
  }

  return merged;
}

export async function resolveScanGeoprivacy(
  userId: string,
  supabaseAdmin: SupabaseClient,
  explicitGeoprivacy?: string | null,
): Promise<ScanGeoprivacy> {
  if (isScanGeoprivacy(explicitGeoprivacy)) {
    return explicitGeoprivacy;
  }

  const { data, error } = await supabaseAdmin
    .from("users")
    .select("default_geoprivacy")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`resolveScanGeoprivacy: ${error.message}`);
  }

  const defaultGeoprivacy = (data as { default_geoprivacy?: unknown } | null)
    ?.default_geoprivacy;
  return isScanGeoprivacy(defaultGeoprivacy) ? defaultGeoprivacy : "open";
}

export async function upsertGhostUserIfMissing(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const cachedResolution = getCachedTierResolution(userId);
  if (cachedResolution?.user_exists === false) {
    await supabaseAdmin
      .from("users")
      .upsert(
        { id: userId, subscription_tier: "free" },
        { onConflict: "id", ignoreDuplicates: true },
      );
    setTierResolutionCache(userId, {
      effective_tier: "pro",
      plan: "pro_trial",
      subscription_tier: "free",
      trial_active: true,
      user_exists: true,
    });
    return;
  }

  if (!hasTierCached(userId)) {
    const { data: existingUser } = await supabaseAdmin
      .from("users")
      .select("subscription_tier, created_at, subscription_expires_at")
      .eq("id", userId)
      .maybeSingle();
    if (existingUser) {
      setTierResolutionCache(userId, {
        ...resolutionForUserRow(existingUser),
        user_exists: true,
      });
    } else {
      await supabaseAdmin
        .from("users")
        .upsert(
          { id: userId, subscription_tier: "free" },
          { onConflict: "id", ignoreDuplicates: true },
        );
      setTierResolutionCache(userId, {
        effective_tier: "pro",
        plan: "pro_trial",
        subscription_tier: "free",
        trial_active: true,
        user_exists: true,
      });
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
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
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

  const speciesId = row?.id ?? null;
  if (speciesId) {
    await upsertSpeciesReferenceImages(
      speciesId,
      data.reference_image_url,
      data.wikipedia_url,
      supabaseAdmin,
    );
    await recordSpeciesContentProvenance(
      supabaseAdmin,
      buildSpeciesDictionaryProvenanceRows(speciesId, data),
      "upsertSpeciesDictionary",
    );
  }

  return speciesId;
}

export interface SpeciesReferenceImageUpsertRow {
  species_id: string;
  url: string;
  source: PublicReferenceImageSource;
  sort_order: number;
  last_verified_at: string;
}

export function speciesReferenceImageRowsFromCache(
  speciesId: string,
  referenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
): SpeciesReferenceImageUpsertRow[] {
  const seen = new Set<string>();
  const rows: SpeciesReferenceImageUpsertRow[] = [];
  const verifiedAt = new Date().toISOString();
  for (const url of legacyReferenceImageUrls(referenceImageUrl)) {
    if (seen.has(url)) continue;
    seen.add(url);
    rows.push({
      species_id: speciesId,
      url,
      source: referenceImageSource(url, wikipediaUrl, rows.length),
      sort_order: rows.length,
      last_verified_at: verifiedAt,
    });
  }

  return rows;
}

async function upsertSpeciesReferenceImages(
  speciesId: string,
  referenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const rows = speciesReferenceImageRowsFromCache(
    speciesId,
    referenceImageUrl,
    wikipediaUrl,
  );
  if (rows.length === 0) return;

  const { error } = await supabaseAdmin
    .from("species_reference_images")
    .upsert(rows, { onConflict: "species_id,url", ignoreDuplicates: false });

  if (error) {
    console.error(
      "[upsertSpeciesReferenceImages] Failed to normalize reference images:",
      error.message,
    );
  }
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
      "updateGroupTags",
    );
  }
}

export interface ScanInsertRow {
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
  blur_score?: number;
  zoom_factor?: number | null;
  ecology_type?: string | null;
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
  depth_scale_text?: string;
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
  video_storage_urls?: string[];
  audio_storage_urls?: string[];
  captured_media?: unknown[] | null;
  life_stage?: string;
  reproductive_condition?: string;
  sex?: string | null;
  sex_confidence?: number | null;
  sex_evidence?: string | null;
  individual_count?: number | null;
  ecological_interactions: string[];
  estimated_size_cm?: number | null;
  inference_tier: string;
  candidates?: IdentificationCandidate[] | null;
  image_quality_score?: number | null;
  is_live_capture?: boolean;
  pet_identification?: PetIdentification | null;
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
  const geoprivacy = await resolveScanGeoprivacy(
    row.user_id,
    supabaseAdmin,
    row.geoprivacy,
  );
  const scanRow = {
    ...row,
    geoprivacy,
    ecology_type: normalizeScanEcologyType(row.ecology_type),
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
