import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type ExternalEnrichmentData,
  fetchExternalEnrichment,
} from "../_shared/external.ts";
import type { SimilarSpeciesEntry } from "../_shared/biology.ts";
import {
  buildPublicSpeciesDictionaryPayload,
  firstReferenceImageUrl,
  firstReferenceImageUrlsBySpeciesId,
  type PublicReferenceImageSource,
  type PublicSimilarSpecies,
  publicSimilarSpeciesMetadata,
  type PublicSpeciesDictionaryPayload,
  type PublicSpeciesDictionaryRow,
  publicSpeciesProjectionForbiddenKeys,
  type PublicSpeciesReferenceImage,
  type PublicSpeciesReferenceImageRow,
  type PublicSpeciesTaxonomy,
  referenceImagesFromLegacyCache as referenceImagesFrom,
  referenceImagesFromRows,
  resolveOptionalPublicCommonName,
  resolvePublicCommonName as resolveCommonName,
  sanitizeAlternativeCommonNames,
  stringValue,
} from "../_shared/publicSpeciesProjection.ts";

export {
  firstReferenceImageUrl,
  publicSpeciesProjectionForbiddenKeys,
  referenceImagesFrom,
  referenceImagesFromRows,
  resolveCommonName,
  sanitizeAlternativeCommonNames,
};

export type ReferenceImageSource = PublicReferenceImageSource;
export type SpeciesDictionaryTaxonomy = PublicSpeciesTaxonomy;
export type SpeciesDictionaryReferenceImage = PublicSpeciesReferenceImage;
export type SpeciesDictionarySimilarSpecies = PublicSimilarSpecies;
export type SpeciesDictionaryPayload = PublicSpeciesDictionaryPayload;
export type SpeciesDictionaryRow = PublicSpeciesDictionaryRow;
export type SpeciesReferenceImageRow = PublicSpeciesReferenceImageRow;

export const buildSpeciesDictionaryPayload =
  buildPublicSpeciesDictionaryPayload;

interface LookalikeRelationRow {
  reason?: string | null;
  visual_traits?: string[] | null;
  confidence?: number | null;
  source?: string | null;
  review_status?: string | null;
  is_bidirectional?: boolean | null;
  sort_order?: number | null;
  lookalike?: LookalikeSpeciesRow | LookalikeSpeciesRow[] | null;
}

interface LookalikeSpeciesRow {
  id?: string | null;
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string | null;
}

export interface SpeciesDictionaryCatalogCursor {
  scientificName: string;
  speciesId: string;
}

export interface SpeciesDictionaryCatalogRequest {
  mode: "catalog";
  query?: string;
  limit: number;
  cursor?: SpeciesDictionaryCatalogCursor;
}

export interface SpeciesDictionaryCatalogItem {
  id: string;
  scientific_name: string;
  common_name: string;
  content_quality: string;
  taxonomy: SpeciesDictionaryTaxonomy | null;
  iucn_red_list_status: string | null;
  hazard_type: string | null;
  group_tags: string[];
  reference_image_url: string | null;
}

export interface SpeciesDictionaryCatalogResult {
  data: SpeciesDictionaryCatalogItem[];
  nextCursor: SpeciesDictionaryCatalogCursor | null;
}

export interface SpeciesDictionaryRequestResult {
  mode?: "catalog";
  speciesId?: string;
  scientificName?: string;
  query?: string;
  limit?: number;
  cursor?: SpeciesDictionaryCatalogCursor;
  error?: string;
  status?: number;
}

export function parseSpeciesDictionaryRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  if (body.mode === "catalog") {
    return parseSpeciesDictionaryCatalogRequest(body);
  }

  if (body.mode !== undefined && body.mode !== null) {
    return { error: "mode must be catalog when provided.", status: 400 };
  }

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

export function parseSpeciesDictionaryCatalogRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  const limit = normalizeCatalogLimit(body.limit);
  if (limit?.error) return limit;

  const query = normalizeOptionalCatalogQuery(body.query);
  if (query?.error) return query;

  const cursor = normalizeOptionalCatalogCursor(body.cursor);
  if (cursor?.error) return cursor;

  const result: SpeciesDictionaryRequestResult = {
    mode: "catalog",
    limit: limit?.limit ?? 40,
  };
  if (query?.query) result.query = query.query;
  if (cursor?.cursor) result.cursor = cursor.cursor;
  return result;
}

export async function fetchSpeciesDictionaryCatalog(
  request: SpeciesDictionaryCatalogRequest,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryCatalogResult> {
  const requestedLimit = Math.max(1, Math.min(100, Math.floor(request.limit)));
  const fetchLimit = requestedLimit + 1;
  const queryText = request.query?.trim().replace(/\s+/g, " ");

  let catalogQuery = supabaseAdmin
    .from("species_dictionary")
    .select(
      "id, scientific_name, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, wikipedia_overview, hazard_type, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags",
    )
    .order("scientific_name", { ascending: true })
    .order("id", { ascending: true })
    .limit(fetchLimit);

  if (queryText) {
    catalogQuery = catalogQuery.ilike("scientific_name", `%${queryText}%`);
  }

  if (request.cursor) {
    catalogQuery = catalogQuery.or(
      `scientific_name.gt.${request.cursor.scientificName},and(scientific_name.eq.${request.cursor.scientificName},id.gt.${request.cursor.speciesId})`,
    );
  }

  const { data, error } = await catalogQuery;
  if (error) {
    throw new Error(
      `Failed to fetch species dictionary catalog: ${error.message}`,
    );
  }

  const rows = ((data ?? []) as SpeciesDictionaryRow[]).slice(0, fetchLimit);
  const visibleRows = rows.slice(0, requestedLimit);
  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    visibleRows.map((row) => row.id),
    supabaseAdmin,
  );
  const items = visibleRows.map((row) =>
    buildSpeciesDictionaryCatalogItem(
      row,
      firstImageBySpeciesId.get(row.id) ??
        firstReferenceImageUrl(row.reference_image_url),
    )
  );
  const lastVisibleRow = visibleRows[visibleRows.length - 1];
  const nextCursor = rows.length > requestedLimit && lastVisibleRow
    ? {
      scientificName: lastVisibleRow.scientific_name,
      speciesId: lastVisibleRow.id,
    }
    : null;

  return { data: items, nextCursor };
}

export function buildSpeciesDictionaryCatalogItem(
  row: SpeciesDictionaryRow,
  referenceImageUrl: string | null = firstReferenceImageUrl(
    row.reference_image_url,
  ),
): SpeciesDictionaryCatalogItem {
  const payload = buildSpeciesDictionaryPayload(row, [], referenceImageUrl
    ? [{ url: referenceImageUrl, source: "gbif" }]
    : []);

  return {
    id: payload.id,
    scientific_name: payload.scientific_name,
    common_name: payload.common_name,
    content_quality: payload.content_quality,
    taxonomy: payload.taxonomy,
    iucn_red_list_status: payload.iucn_red_list_status,
    hazard_type: payload.hazard_type,
    group_tags: payload.group_tags,
    reference_image_url: referenceImageUrl,
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
  if (!row) {
    return normalizedLookup.scientificName
      ? await fetchExternalSpeciesDictionary(normalizedLookup.scientificName)
      : null;
  }

  const similarSpecies = await fetchSimilarSpecies(row.id, supabaseAdmin);
  const referenceImages = await fetchReferenceImages(
    row.id,
    row.reference_image_url,
    row.wikipedia_url,
    supabaseAdmin,
  );
  return buildSpeciesDictionaryPayload(row, similarSpecies, referenceImages);
}

export async function fetchExternalSpeciesDictionary(
  scientificName: string,
): Promise<SpeciesDictionaryPayload> {
  const normalizedScientificName = scientificName.trim().replace(/\s+/g, " ");
  const externalData = await fetchExternalEnrichment(normalizedScientificName);
  const taxonomy = externalData.gbifTaxonomy;
  const { fetchSimilarSpecies: fetchModelSimilarSpecies } = await import(
    "../_shared/biology.ts"
  );
  const similarResult = await fetchModelSimilarSpecies(
    "species-dictionary-public",
    normalizedScientificName,
    taxonomy,
  );
  const similarSpecies = externalSimilarSpecies(
    similarResult?.similar_species ?? [],
  );

  return buildExternalSpeciesDictionaryPayload(
    normalizedScientificName,
    externalData,
    similarSpecies,
  );
}

export function buildExternalSpeciesDictionaryPayload(
  scientificName: string,
  externalData: ExternalEnrichmentData,
  similarSpecies: SpeciesDictionarySimilarSpecies[] = [],
): SpeciesDictionaryPayload {
  const normalizedScientificName = scientificName.trim().replace(/\s+/g, " ");
  return buildSpeciesDictionaryPayload(
    externalSpeciesRow(normalizedScientificName, externalData),
    similarSpecies,
  );
}

function externalSpeciesRow(
  scientificName: string,
  externalData: ExternalEnrichmentData,
): SpeciesDictionaryRow {
  const taxonomy = externalData.gbifTaxonomy;
  const commonName = externalCommonName(scientificName, externalData);

  return {
    id: externalSpeciesId(scientificName),
    scientific_name: scientificName,
    common_names: commonName ? { en: commonName } : null,
    alternative_common_names: externalData.alternativeCommonNames,
    kingdom: taxonomy?.kingdom ?? null,
    phylum: taxonomy?.phylum ?? null,
    class: taxonomy?.class ?? null,
    order: taxonomy?.order ?? null,
    family: taxonomy?.family ?? null,
    genus: taxonomy?.genus ?? null,
    wikipedia_url: externalData.wikipediaUrl,
    reference_image_url: externalData.referenceImageUrl,
    wikipedia_overview: externalData.wikiExtract,
    hazard_type: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: externalData.gbifKey,
    group_tags: [],
  };
}

function externalSimilarSpecies(
  entries: SimilarSpeciesEntry[],
): SpeciesDictionarySimilarSpecies[] {
  return entries.map((entry, index) => ({
    scientific_name: entry.scientific_name,
    common_name: entry.common_name,
    reference_image_url: null,
    iucn_red_list_status: null,
    reason: stringValue(entry.reason),
    visual_traits: Array.isArray(entry.visual_traits)
      ? entry.visual_traits
      : [],
    confidence:
      typeof entry.confidence === "number" && Number.isFinite(entry.confidence)
        ? Math.max(0, Math.min(1, entry.confidence))
        : null,
    source: "model_enrichment",
    review_status: "unreviewed",
    is_bidirectional: false,
    sort_order: index,
  }));
}

function externalCommonName(
  scientificName: string,
  externalData: ExternalEnrichmentData,
): string | null {
  const wikiTitle = stringValue(externalData.wikiTitle)
    ?.replace(/\s*\([^)]+\)$/, "")
    .trim();
  if (wikiTitle && wikiTitle.toLowerCase() !== scientificName.toLowerCase()) {
    return wikiTitle;
  }

  return externalData.alternativeCommonNames[0] ?? null;
}

function externalSpeciesId(scientificName: string): string {
  return `external:${encodeURIComponent(scientificName.toLowerCase())}`;
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
      "reason, visual_traits, confidence, source, review_status, is_bidirectional, sort_order, lookalike:species_dictionary!lookalike_id(id, scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId)
    .neq("review_status", "rejected")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });

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
    relation: LookalikeRelationRow;
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
      common_name: resolveOptionalPublicCommonName(lookalike?.common_names),
      legacy_reference_image_url: stringValue(lookalike?.reference_image_url),
      iucn_red_list_status: stringValue(lookalike?.iucn_red_list_status),
      relation: row,
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
    ...publicSimilarSpeciesMetadata(row.relation),
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

  return firstReferenceImageUrlsBySpeciesId(
    data as SpeciesReferenceImageRow[] | null,
  );
}

function relationValue<T>(value: T | T[] | null | undefined): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
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

function normalizeCatalogLimit(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return { error: "limit must be a number when provided.", status: 400 };
  }

  return { limit: Math.max(1, Math.min(100, Math.floor(value))) };
}

function normalizeOptionalCatalogQuery(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return { error: "query must be a string when provided.", status: 400 };
  }

  const query = value.trim().replace(/\s+/g, " ");
  if (!query) return undefined;
  if (query.length > 80) {
    return { error: "query is too long.", status: 400 };
  }

  return { query };
}

function normalizeOptionalCatalogCursor(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "object" || Array.isArray(value)) {
    return { error: "cursor must be an object when provided.", status: 400 };
  }

  const cursor = value as Record<string, unknown>;
  const scientificNameValue = cursor.scientific_name ?? cursor.scientificName;
  const speciesIdValue = cursor.species_id ?? cursor.speciesId;

  if (typeof scientificNameValue !== "string") {
    return { error: "cursor.scientific_name must be a string.", status: 400 };
  }
  if (typeof speciesIdValue !== "string" || !isUuid(speciesIdValue.trim())) {
    return { error: "cursor.species_id must be a valid UUID.", status: 400 };
  }

  const scientificName = scientificNameValue.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return { error: "cursor.scientific_name must be a string.", status: 400 };
  }
  if (scientificName.length > 160) {
    return { error: "cursor.scientific_name is too long.", status: 400 };
  }

  return {
    cursor: {
      scientificName,
      speciesId: speciesIdValue.trim(),
    },
  };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    value,
  );
}
