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
  license?: string;
  attribution?: string;
  width?: number;
  height?: number;
}

export interface SpeciesDictionarySimilarSpecies {
  species_id: string;
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
  id?: string | null;
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string | null;
}

export interface SpeciesReferenceImageRow {
  id?: string | null;
  species_id?: string | null;
  url?: string | null;
  source?: string | null;
  license?: string | null;
  attribution?: string | null;
  width?: number | null;
  height?: number | null;
  sort_order?: number | null;
  created_at?: string | null;
}

export interface SpeciesDictionaryRequestResult {
  speciesId?: string;
  scientificName?: string;
  error?: string;
  status?: number;
}

export function parseSpeciesDictionaryRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  const rawSpeciesId = body.species_id;
  if (rawSpeciesId !== undefined && rawSpeciesId !== null) {
    if (typeof rawSpeciesId !== "string") {
      return { error: "species_id must be a valid UUID.", status: 400 };
    }

    const speciesId = rawSpeciesId.trim();
    if (speciesId && !isUuid(speciesId)) {
      return { error: "species_id must be a valid UUID.", status: 400 };
    }

    if (speciesId) {
      const scientificName = normalizeOptionalScientificName(
        body.scientific_name,
      );
      if (scientificName?.error) return scientificName;
      return scientificName?.scientificName
        ? { speciesId, scientificName: scientificName.scientificName }
        : { speciesId };
    }
  }

  const rawName = body.scientific_name;
  if (typeof rawName !== "string") {
    return {
      error: "Missing required parameter: species_id or scientific_name",
      status: 400,
    };
  }

  const scientificName = rawName.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return {
      error: "Missing required parameter: species_id or scientific_name",
      status: 400,
    };
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

export function referenceImagesFromRows(
  rows: SpeciesReferenceImageRow[] | null | undefined,
  wikipediaUrl: string | null | undefined,
): SpeciesDictionaryReferenceImage[] {
  const seen = new Set<string>();
  const images: SpeciesDictionaryReferenceImage[] = [];

  for (const row of rows ?? []) {
    const url = stringValue(row.url);
    if (!url || seen.has(url)) continue;
    seen.add(url);

    const image: SpeciesDictionaryReferenceImage = {
      url,
      source: normalizedReferenceImageSource(
        row.source,
        url,
        wikipediaUrl,
        images.length,
      ),
    };

    const license = stringValue(row.license);
    if (license) image.license = license;

    const attribution = stringValue(row.attribution);
    if (attribution) image.attribution = attribution;

    const width = positiveInteger(row.width);
    if (width !== null) image.width = width;

    const height = positiveInteger(row.height);
    if (height !== null) image.height = height;

    images.push(image);
  }

  return images;
}

export function firstReferenceImageUrl(
  referenceImageUrl: string | null | undefined,
): string | null {
  return referenceImagesFrom(referenceImageUrl, null)[0]?.url ?? null;
}

export function buildSpeciesDictionaryPayload(
  row: SpeciesDictionaryRow,
  similarSpecies: SpeciesDictionarySimilarSpecies[],
  referenceImages?: SpeciesDictionaryReferenceImage[],
): SpeciesDictionaryPayload {
  const commonName = resolveCommonName(row.common_names, row.scientific_name);

  return {
    id: row.id,
    scientific_name: row.scientific_name,
    common_name: commonName,
    alternative_common_names: sanitizeAlternativeCommonNames(
      row.alternative_common_names,
      commonName,
    ),
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
    reference_images: referenceImages ??
      referenceImagesFrom(row.reference_image_url, row.wikipedia_url),
    similar_species: similarSpecies,
  };
}

export async function fetchSpeciesDictionary(
  lookup: string | { speciesId?: string; scientificName?: string },
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryPayload | null> {
  const normalizedLookup = typeof lookup === "string"
    ? { scientificName: lookup }
    : lookup;
  const query = supabaseAdmin
    .from("species_dictionary")
    .select(
      "id, scientific_name, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, wikipedia_overview, hazard_type, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags",
    )
    .limit(1);

  const { data: speciesRows, error: speciesError } = normalizedLookup.speciesId
    ? await query.eq("id", normalizedLookup.speciesId)
    : await query.eq("scientific_name", normalizedLookup.scientificName ?? "");

  if (speciesError) {
    throw new Error(
      `Failed to fetch species dictionary row: ${speciesError.message}`,
    );
  }

  const row = ((speciesRows ?? []) as SpeciesDictionaryRow[])[0];
  if (!row) return null;

  const similarSpecies = await fetchSimilarSpecies(row.id, supabaseAdmin);
  const referenceImages = await fetchReferenceImages(
    row.id,
    row.reference_image_url,
    row.wikipedia_url,
    supabaseAdmin,
  );
  return buildSpeciesDictionaryPayload(row, similarSpecies, referenceImages);
}

async function fetchReferenceImages(
  speciesId: string,
  legacyReferenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryReferenceImage[]> {
  const { data, error } = await supabaseAdmin
    .from("species_reference_images")
    .select(
      "id, url, source, license, attribution, width, height, sort_order, created_at",
    )
    .eq("species_id", speciesId)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw new Error(
      `Failed to fetch species reference images: ${error.message}`,
    );
  }

  const normalizedImages = referenceImagesFromRows(
    data as SpeciesReferenceImageRow[] | null,
    wikipediaUrl,
  );
  return normalizedImages.length > 0
    ? normalizedImages
    : referenceImagesFrom(legacyReferenceImageUrl, wikipediaUrl);
}

async function fetchSimilarSpecies(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionarySimilarSpecies[]> {
  const { data, error } = await supabaseAdmin
    .from("species_lookalikes")
    .select(
      "lookalike:species_dictionary!lookalike_id(id, scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId);

  if (error) {
    throw new Error(`Failed to fetch species lookalikes: ${error.message}`);
  }

  const seen = new Set<string>();
  const rows: Array<{
    species_id: string;
    scientific_name: string;
    common_name: string | null;
    legacy_reference_image_url: string | null;
    iucn_red_list_status: string | null;
  }> = [];

  for (const row of (data ?? []) as LookalikeRelationRow[]) {
    const lookalike = relationValue(row.lookalike);
    const lookalikeId = stringValue(lookalike?.id);
    const scientificName = stringValue(lookalike?.scientific_name);
    if (!lookalikeId || !scientificName) continue;

    const key = lookalikeId.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    rows.push({
      species_id: lookalikeId,
      scientific_name: scientificName,
      common_name: resolveOptionalCommonName(lookalike?.common_names),
      legacy_reference_image_url: stringValue(lookalike?.reference_image_url),
      iucn_red_list_status: stringValue(lookalike?.iucn_red_list_status),
    });
  }

  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    rows.map((row) => row.species_id),
    supabaseAdmin,
  );

  return rows.map((row) => ({
    species_id: row.species_id,
    scientific_name: row.scientific_name,
    common_name: row.common_name,
    reference_image_url: firstImageBySpeciesId.get(row.species_id) ??
      firstReferenceImageUrl(row.legacy_reference_image_url),
    iucn_red_list_status: row.iucn_red_list_status,
  }));
}

async function fetchFirstReferenceImagesForSpecies(
  speciesIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<Map<string, string>> {
  const uniqueSpeciesIds = Array.from(
    new Set(speciesIds.filter((id) => id.length > 0)),
  );
  if (uniqueSpeciesIds.length === 0) return new Map();

  const { data, error } = await supabaseAdmin
    .from("species_reference_images")
    .select("id, species_id, url, sort_order, created_at")
    .in("species_id", uniqueSpeciesIds)
    .order("species_id", { ascending: true })
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw new Error(
      `Failed to fetch lookalike reference images: ${error.message}`,
    );
  }

  const firstImageBySpeciesId = new Map<string, string>();
  for (const row of (data ?? []) as SpeciesReferenceImageRow[]) {
    const speciesId = stringValue(row.species_id);
    const url = stringValue(row.url);
    if (!speciesId || !url || firstImageBySpeciesId.has(speciesId)) continue;
    firstImageBySpeciesId.set(speciesId, url);
  }

  return firstImageBySpeciesId;
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

function normalizedReferenceImageSource(
  source: string | null | undefined,
  urlString: string,
  wikipediaUrl: string | null | undefined,
  index: number,
): ReferenceImageSource {
  if (source === "wikipedia" || source === "gbif") return source;
  return referenceImageSource(urlString, wikipediaUrl, index);
}

function resolveOptionalCommonName(
  commonNames: Record<string, unknown> | null | undefined,
): string | null {
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

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : null;
}

function normalizeOptionalScientificName(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return {
      error: "scientific_name must be a string when provided.",
      status: 400,
    };
  }

  const scientificName = value.trim().replace(/\s+/g, " ");
  if (!scientificName) return undefined;
  if (scientificName.length > 160) {
    return { error: "scientific_name is too long.", status: 400 };
  }

  return { scientificName };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    value,
  );
}
