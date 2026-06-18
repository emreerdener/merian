export type PublicReferenceImageSource = "wikipedia" | "gbif" | "merian";
export type PublicSpeciesContentQuality =
  | "complete"
  | "sparse"
  | "needs_enrichment";

export const PUBLIC_SPECIES_SCHEMA_VERSION = 1;

export interface PublicSpeciesTaxonomy {
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
}

export interface PublicSpeciesReferenceImage {
  url: string;
  source: PublicReferenceImageSource;
  license?: string;
  attribution?: string;
  width?: number;
  height?: number;
}

export interface PublicSpeciesReferenceImageRow {
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

interface PublicSpeciesReferenceImageCandidate {
  id: string | null;
  url: string;
  source: PublicReferenceImageSource;
  license?: string;
  attribution?: string;
  width?: number;
  height?: number;
  sortOrder: number;
  createdAt: string | null;
  originalIndex: number;
}

export interface PublicReferenceImageAttributionIssue {
  url: string;
  source: PublicReferenceImageSource;
  missing: Array<"license" | "attribution">;
}

export interface PublicSpeciesDictionaryRow {
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
  native_region?: string | null;
  created_at?: string | null;
}

export interface PublicSimilarSpecies {
  species_id?: string | null;
  scientific_name: string;
  common_name: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
  reason?: string | null;
  visual_traits?: string[];
  confidence?: number | null;
  source?: string | null;
  review_status?: string | null;
  is_bidirectional?: boolean;
  sort_order?: number | null;
}

export interface PublicSpeciesDictionaryPayload {
  id: string;
  scientific_name: string;
  common_name: string;
  content_quality: PublicSpeciesContentQuality;
  alternative_common_names: string[];
  taxonomy: PublicSpeciesTaxonomy;
  hazard_type: string | null;
  iucn_red_list_status: string | null;
  wikipedia_url: string | null;
  wikipedia_overview: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  group_tags: string[];
  reference_images: PublicSpeciesReferenceImage[];
  similar_species: PublicSimilarSpecies[];
}

export const PUBLIC_SPECIES_FORBIDDEN_KEYS = [
  "scan_id",
  "scanId",
  "scans",
  "user_id",
  "userId",
  "owner_id",
  "ownerId",
  "post_id",
  "postId",
  "explore_post_id",
  "explorePostId",
  "field_notes",
  "fieldNotes",
  "comments",
  "comment_id",
  "commentId",
  "image_storage_urls",
  "imageStorageUrls",
  "local_media",
  "localMedia",
  "gps_lat_exact",
  "gpsLatExact",
  "gps_long_exact",
  "gpsLongExact",
  "gps_lat_public",
  "gpsLatPublic",
  "gps_long_public",
  "gpsLongPublic",
  "latitude",
  "longitude",
  "coordinate_uncertainty_in_meters",
  "coordinateUncertaintyInMeters",
  "geoprivacy",
  "ai_reasoning",
  "aiReasoning",
  "user_review_state",
  "userReviewState",
  "user_identification_override",
  "userIdentificationOverride",
  "preferred_common_name",
  "preferredCommonName",
] as const;

const FORBIDDEN_KEY_SET = new Set<string>(PUBLIC_SPECIES_FORBIDDEN_KEYS);

export function resolvePublicCommonName(
  commonNames: Record<string, unknown> | null | undefined,
  fallbackName: string,
): string {
  return resolveOptionalPublicCommonName(commonNames, fallbackName) ??
    fallbackName;
}

export function resolveOptionalPublicCommonName(
  commonNames: Record<string, unknown> | null | undefined,
  fallbackName?: string | null,
): string | null {
  const englishName = stringValue(commonNames?.en);
  if (englishName) return englishName;

  for (const value of Object.values(commonNames ?? {})) {
    const fallback = stringValue(value);
    if (fallback) return fallback;
  }

  return stringValue(fallbackName);
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

export function sanitizePublicStringArray(
  values: string[] | null | undefined,
): string[] {
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

export function sanitizeLookalikeVisualTraits(
  values: unknown,
  maxCount = 5,
): string[] {
  if (!Array.isArray(values)) return [];
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values) {
    const trimmed = stringValue(value);
    if (!trimmed) continue;

    const normalized = trimmed.toLowerCase();
    if (seen.has(normalized)) continue;

    seen.add(normalized);
    result.push(trimmed.slice(0, 80));
    if (result.length >= maxCount) break;
  }

  return result;
}

export function normalizePublicConfidence(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.max(0, Math.min(1, value));
}

export function publicSimilarSpeciesMetadata(
  relation: {
    reason?: unknown;
    visual_traits?: unknown;
    confidence?: unknown;
    source?: unknown;
    review_status?: unknown;
    is_bidirectional?: unknown;
    sort_order?: unknown;
  },
): Pick<
  PublicSimilarSpecies,
  | "reason"
  | "visual_traits"
  | "confidence"
  | "source"
  | "review_status"
  | "is_bidirectional"
  | "sort_order"
> {
  return {
    reason: stringValue(relation.reason),
    visual_traits: sanitizeLookalikeVisualTraits(relation.visual_traits),
    confidence: normalizePublicConfidence(relation.confidence),
    source: stringValue(relation.source),
    review_status: stringValue(relation.review_status),
    is_bidirectional: relation.is_bidirectional === true,
    sort_order: typeof relation.sort_order === "number" &&
        Number.isInteger(relation.sort_order) && relation.sort_order >= 0
      ? relation.sort_order
      : null,
  };
}

export function legacyReferenceImageUrls(
  referenceImageUrl: string | null | undefined,
): string[] {
  return (referenceImageUrl ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

export function referenceImagesFromLegacyCache(
  referenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
): PublicSpeciesReferenceImage[] {
  const seen = new Set<string>();
  const images: PublicSpeciesReferenceImage[] = [];

  for (const url of legacyReferenceImageUrls(referenceImageUrl)) {
    if (seen.has(url)) continue;
    seen.add(url);
    images.push({
      url,
      source: referenceImageSource(url, wikipediaUrl, images.length),
    });
  }

  return images;
}

export function referenceImagesFromRows(
  rows: PublicSpeciesReferenceImageRow[] | null | undefined,
  wikipediaUrl: string | null | undefined,
): PublicSpeciesReferenceImage[] {
  const seen = new Set<string>();
  const images: PublicSpeciesReferenceImage[] = [];
  const candidates: PublicSpeciesReferenceImageCandidate[] = [];

  for (const [index, row] of (rows ?? []).entries()) {
    const url = stringValue(row.url);
    if (!url) continue;

    const source = normalizedReferenceImageSource(
      row.source,
      url,
      wikipediaUrl,
      index,
    );
    const candidate: PublicSpeciesReferenceImageCandidate = {
      id: stringValue(row.id),
      url,
      source,
      sortOrder: positiveIntegerOrZero(row.sort_order) ?? index,
      createdAt: stringValue(row.created_at),
      originalIndex: index,
    };

    const license = stringValue(row.license);
    if (license) candidate.license = license;

    const attribution = stringValue(row.attribution);
    if (attribution) candidate.attribution = attribution;

    const width = positiveInteger(row.width);
    if (width !== null) candidate.width = width;

    const height = positiveInteger(row.height);
    if (height !== null) candidate.height = height;

    candidates.push(candidate);
  }

  for (const candidate of candidates.sort(compareReferenceImageCandidates)) {
    if (seen.has(candidate.url)) continue;
    seen.add(candidate.url);

    const image: PublicSpeciesReferenceImage = {
      url: candidate.url,
      source: candidate.source,
    };

    if (candidate.license) image.license = candidate.license;
    if (candidate.attribution) image.attribution = candidate.attribution;
    if (candidate.width !== undefined) image.width = candidate.width;
    if (candidate.height !== undefined) image.height = candidate.height;

    images.push(image);
  }

  return images;
}

export function publicWebReferenceImageAttributionIssues(
  images: PublicSpeciesReferenceImage[],
): PublicReferenceImageAttributionIssue[] {
  return images.flatMap((image) => {
    const missing: Array<"license" | "attribution"> = [];
    if (!stringValue(image.license)) missing.push("license");
    if (!stringValue(image.attribution)) missing.push("attribution");

    return missing.length > 0
      ? [{ url: image.url, source: image.source, missing }]
      : [];
  });
}

export function firstReferenceImageUrl(
  referenceImageUrl: string | null | undefined,
): string | null {
  return referenceImagesFromLegacyCache(referenceImageUrl, null)[0]?.url ??
    null;
}

export function firstReferenceImageUrlsBySpeciesId(
  rows: PublicSpeciesReferenceImageRow[] | null | undefined,
): Map<string, string> {
  const firstImageBySpeciesId = new Map<string, string>();
  const sortedRows = [...(rows ?? [])].sort(compareReferenceImageRows);

  for (const row of sortedRows) {
    const speciesId = stringValue(row.species_id);
    const url = stringValue(row.url);
    if (!speciesId || !url || firstImageBySpeciesId.has(speciesId)) continue;
    firstImageBySpeciesId.set(speciesId, url);
  }

  return firstImageBySpeciesId;
}

export function buildPublicSpeciesDictionaryPayload(
  row: PublicSpeciesDictionaryRow,
  similarSpecies: PublicSimilarSpecies[],
  referenceImages?: PublicSpeciesReferenceImage[],
): PublicSpeciesDictionaryPayload {
  const commonName = resolvePublicCommonName(
    row.common_names,
    row.scientific_name,
  );

  return {
    id: row.id,
    scientific_name: row.scientific_name,
    common_name: commonName,
    content_quality: classifyPublicSpeciesContentQuality(
      row,
      referenceImages,
    ),
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
    group_tags: sanitizePublicStringArray(row.group_tags),
    reference_images: referenceImages ??
      referenceImagesFromLegacyCache(
        row.reference_image_url,
        row.wikipedia_url,
      ),
    similar_species: similarSpecies,
  };
}

export function classifyPublicSpeciesContentQuality(
  row: PublicSpeciesDictionaryRow,
  referenceImages?: PublicSpeciesReferenceImage[],
): PublicSpeciesContentQuality {
  const images = referenceImages ??
    referenceImagesFromLegacyCache(row.reference_image_url, row.wikipedia_url);
  const contentSignals = [
    images.length > 0,
    hasPublicOverview(row),
    hasPublicHabitatOrDistribution(row),
    hasMeaningfulTaxonomy(row),
  ];
  const signalCount = contentSignals.filter(Boolean).length;

  if (signalCount === contentSignals.length) return "complete";
  if (signalCount >= 2) return "sparse";
  return "needs_enrichment";
}

export function publicSpeciesProjectionForbiddenKeys(
  value: unknown,
): string[] {
  const hits: string[] = [];
  collectForbiddenKeys(value, "$", hits);
  return hits;
}

export function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function referenceImageSource(
  urlString: string,
  wikipediaUrl: string | null | undefined,
  index: number,
): PublicReferenceImageSource {
  try {
    const host = new URL(urlString).host.toLowerCase();
    if (host === "media.merian.app" || host.endsWith(".merian.app")) {
      return "merian";
    }

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
): PublicReferenceImageSource {
  if (source === "wikipedia" || source === "gbif" || source === "merian") {
    return source;
  }
  return referenceImageSource(urlString, wikipediaUrl, index);
}

export function publicReferenceImageSourceRank(
  source: PublicReferenceImageSource,
): number {
  switch (source) {
    case "merian":
      return 0;
    case "wikipedia":
      return 1;
    case "gbif":
      return 2;
  }
}

function compareReferenceImageCandidates(
  lhs: PublicSpeciesReferenceImageCandidate,
  rhs: PublicSpeciesReferenceImageCandidate,
): number {
  return publicReferenceImageSourceRank(lhs.source) -
      publicReferenceImageSourceRank(rhs.source) ||
    lhs.sortOrder - rhs.sortOrder ||
    compareNullableString(lhs.createdAt, rhs.createdAt) ||
    compareNullableString(lhs.id, rhs.id) ||
    lhs.originalIndex - rhs.originalIndex;
}

function compareReferenceImageRows(
  lhs: PublicSpeciesReferenceImageRow,
  rhs: PublicSpeciesReferenceImageRow,
): number {
  const lhsSource = normalizedReferenceImageSource(
    lhs.source,
    lhs.url ?? "",
    null,
    0,
  );
  const rhsSource = normalizedReferenceImageSource(
    rhs.source,
    rhs.url ?? "",
    null,
    0,
  );
  const lhsSortOrder = positiveIntegerOrZero(lhs.sort_order) ?? 0;
  const rhsSortOrder = positiveIntegerOrZero(rhs.sort_order) ?? 0;

  return compareNullableString(
    lhs.species_id ?? null,
    rhs.species_id ?? null,
  ) ||
    publicReferenceImageSourceRank(lhsSource) -
      publicReferenceImageSourceRank(rhsSource) ||
    lhsSortOrder - rhsSortOrder ||
    compareNullableString(lhs.created_at ?? null, rhs.created_at ?? null) ||
    compareNullableString(lhs.id ?? null, rhs.id ?? null);
}

function compareNullableString(
  lhs: string | null,
  rhs: string | null,
): number {
  if (lhs === rhs) return 0;
  if (lhs === null) return 1;
  if (rhs === null) return -1;
  return lhs.localeCompare(rhs);
}

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : null;
}

function positiveIntegerOrZero(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0
    ? value
    : null;
}

function hasPublicOverview(row: PublicSpeciesDictionaryRow): boolean {
  return (stringValue(row.wikipedia_overview)?.length ?? 0) >= 60;
}

function hasPublicHabitatOrDistribution(
  row: PublicSpeciesDictionaryRow,
): boolean {
  return stringValue(row.habitat_description) !== null ||
    positiveInteger(row.gbif_taxon_key) !== null;
}

function hasMeaningfulTaxonomy(row: PublicSpeciesDictionaryRow): boolean {
  const values = [
    row.kingdom,
    row.phylum,
    row.class,
    row.order,
    row.family,
    row.genus,
  ].filter((value) => stringValue(value) !== null);
  return values.length >= 2;
}

function collectForbiddenKeys(
  value: unknown,
  path: string,
  hits: string[],
): void {
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      collectForbiddenKeys(entry, `${path}[${index}]`, hits)
    );
    return;
  }

  if (!value || typeof value !== "object") return;

  for (const [key, child] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    if (FORBIDDEN_KEY_SET.has(key)) hits.push(childPath);
    collectForbiddenKeys(child, childPath, hits);
  }
}
