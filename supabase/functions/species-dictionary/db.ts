import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type ReferenceImageSource = "wikipedia" | "gbif";

export interface SpeciesDictionaryTaxonomy {
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
}

export interface SpeciesDictionaryReferenceImage {
  url: string;
  source: ReferenceImageSource;
}

export interface SpeciesDictionarySimilarSpecies {
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
}

export interface SpeciesDictionaryPayload {
  id: string;
  scientific_name: string;
  common_name: string;
  alternative_common_names: string[];
  taxonomy: SpeciesDictionaryTaxonomy;
  hazard_type: string | null;
  iucn_red_list_status: string | null;
  wikipedia_url: string | null;
  wikipedia_overview: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  group_tags: string[];
  reference_images: SpeciesDictionaryReferenceImage[];
  similar_species: SpeciesDictionarySimilarSpecies[];
}

interface SpeciesDictionaryRow {
  id: string;
  scientific_name: string;
  common_names: Record<string, unknown> | null;
  alternative_common_names: string[] | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  wikipedia_url: string | null;
  reference_image_url: string | null;
  wikipedia_overview: string | null;
  hazard_type: string | null;
  iucn_red_list_status: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  group_tags: string[] | null;
}

interface LookalikeRelationRow {
  lookalike?: LookalikeSpeciesRow | LookalikeSpeciesRow[] | null;
}

interface LookalikeSpeciesRow {
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string | null;
}

export interface SpeciesDictionaryRequestResult {
  scientificName?: string;
  error?: string;
  status?: number;
}

export function parseSpeciesDictionaryRequest(body: Record<string, unknown>): SpeciesDictionaryRequestResult {
  const rawName = body.scientific_name;
  if (typeof rawName !== "string") {
    return { error: "Missing required parameter: scientific_name", status: 400 };
  }

  const scientificName = rawName.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return { error: "Missing required parameter: scientific_name", status: 400 };
  }

  if (scientificName.length > 160) {
    return { error: "scientific_name is too long.", status: 400 };
  }

  return { scientificName };
}

export function resolveCommonName(
  commonNames: Record<string, unknown> | null | undefined,
  scientificName: string,
): string {
  const englishName = stringValue(commonNames?.en);
  if (englishName) return englishName;

  for (const value of Object.values(commonNames ?? {})) {
    const fallback = stringValue(value);
    if (fallback) return fallback;
  }

  return scientificName;
}

export function sanitizeAlternativeCommonNames(
  names: string[] | null | undefined,
  primaryCommonName: string,
): string[] {
  const seen = new Set<string>();
  const primaryKey = primaryCommonName.trim().toLowerCase();
  const sanitized: string[] = [];

  for (const name of names ?? []) {
    const trimmed = name.trim();
    if (!trimmed) continue;

    const key = trimmed.toLowerCase();
    if (key === primaryKey || seen.has(key)) continue;

    seen.add(key);
    sanitized.push(trimmed);
  }

  return sanitized;
}

export function referenceImagesFrom(
  referenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
): SpeciesDictionaryReferenceImage[] {
  const seen = new Set<string>();
  const urls = (referenceImageUrl ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);

  const images: SpeciesDictionaryReferenceImage[] = [];
  for (const [index, url] of urls.entries()) {
    if (seen.has(url)) continue;
    seen.add(url);
    images.push({
      url,
      source: referenceImageSource(url, wikipediaUrl, index),
    });
  }

  return images;
}

export function buildSpeciesDictionaryPayload(
  row: SpeciesDictionaryRow,
  similarSpecies: SpeciesDictionarySimilarSpecies[],
): SpeciesDictionaryPayload {
  const commonName = resolveCommonName(row.common_names, row.scientific_name);

  return {
    id: row.id,
    scientific_name: row.scientific_name,
    common_name: commonName,
    alternative_common_names: sanitizeAlternativeCommonNames(row.alternative_common_names, commonName),
    taxonomy: {
      kingdom: row.kingdom,
      phylum: row.phylum,
      class: row.class,
      order: row.order,
      family: row.family,
      genus: row.genus,
    },
    hazard_type: row.hazard_type,
    iucn_red_list_status: row.iucn_red_list_status,
    wikipedia_url: row.wikipedia_url,
    wikipedia_overview: row.wikipedia_overview,
    habitat_description: row.habitat_description,
    gbif_taxon_key: row.gbif_taxon_key,
    group_tags: sanitizedStringArray(row.group_tags),
    reference_images: referenceImagesFrom(row.reference_image_url, row.wikipedia_url),
    similar_species: similarSpecies,
  };
}

export async function fetchSpeciesDictionary(
  scientificName: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryPayload | null> {
  const { data: speciesRows, error: speciesError } = await supabaseAdmin
    .from("species_dictionary")
    .select(
      "id, scientific_name, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, wikipedia_overview, hazard_type, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags",
    )
    .eq("scientific_name", scientificName)
    .limit(1);

  if (speciesError) {
    throw new Error(`Failed to fetch species dictionary row: ${speciesError.message}`);
  }

  const row = ((speciesRows ?? []) as SpeciesDictionaryRow[])[0];
  if (!row) return null;

  const similarSpecies = await fetchSimilarSpecies(row.id, supabaseAdmin);
  return buildSpeciesDictionaryPayload(row, similarSpecies);
}

async function fetchSimilarSpecies(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionarySimilarSpecies[]> {
  const { data, error } = await supabaseAdmin
    .from("species_lookalikes")
    .select(
      "lookalike:species_dictionary!lookalike_id(scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId);

  if (error) {
    throw new Error(`Failed to fetch species lookalikes: ${error.message}`);
  }

  const seen = new Set<string>();
  const entries: SpeciesDictionarySimilarSpecies[] = [];

  for (const row of (data ?? []) as LookalikeRelationRow[]) {
    const lookalike = relationValue(row.lookalike);
    const scientificName = stringValue(lookalike?.scientific_name);
    if (!scientificName) continue;

    const key = scientificName.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    entries.push({
      scientific_name: scientificName,
      common_name: resolveOptionalCommonName(lookalike?.common_names),
      reference_image_url: stringValue(lookalike?.reference_image_url),
      iucn_red_list_status: stringValue(lookalike?.iucn_red_list_status),
    });
  }

  return entries;
}

function relationValue<T>(value: T | T[] | null | undefined): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function referenceImageSource(
  urlString: string,
  wikipediaUrl: string | null | undefined,
  index: number,
): ReferenceImageSource {
  try {
    const host = new URL(urlString).host.toLowerCase();
    if (host.includes("wikipedia") || host.includes("wikimedia")) {
      return "wikipedia";
    }
  } catch {
    // Fall through to the positional Wikipedia fallback.
  }

  if (index === 0 && stringValue(wikipediaUrl)) {
    return "wikipedia";
  }

  return "gbif";
}

function resolveOptionalCommonName(commonNames: Record<string, unknown> | null | undefined): string | null {
  const englishName = stringValue(commonNames?.en);
  if (englishName) return englishName;

  for (const value of Object.values(commonNames ?? {})) {
    const fallback = stringValue(value);
    if (fallback) return fallback;
  }

  return null;
}

function sanitizedStringArray(values: string[] | null | undefined): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values ?? []) {
    const trimmed = value.trim();
    if (!trimmed) continue;

    const key = trimmed.toLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    result.push(trimmed);
  }

  return result;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
