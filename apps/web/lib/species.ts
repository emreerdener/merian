import { createPublicServerSupabaseClient } from "./supabasePublic.ts";
import {
  publicWebReferenceImageAttributionIssues,
  type PublicSpeciesReferenceImage,
} from "../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SPECIES_SLUG_MAX_LENGTH = 80;

type SpeciesDictionaryInvokerResult = {
  data: unknown;
  error: unknown;
};

export type SpeciesDictionaryInvoker = (
  speciesId: string,
) => Promise<SpeciesDictionaryInvokerResult>;

export type WebSpeciesTaxonomy = {
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
};

export type WebSimilarSpecies = {
  speciesId: string | null;
  scientificName: string;
  commonName: string | null;
  iucnRedListStatus: string | null;
};

export type WebSpeciesDictionaryEntry = {
  id: string;
  scientificName: string;
  commonName: string;
  contentQuality: "complete" | "sparse" | "needs_enrichment";
  alternativeCommonNames: string[];
  taxonomy: WebSpeciesTaxonomy;
  hazardType: string | null;
  iucnRedListStatus: string | null;
  wikipediaUrl: string | null;
  wikipediaOverview: string | null;
  habitatDescription: string | null;
  gbifTaxonKey: number | null;
  groupTags: string[];
  referenceImages: PublicSpeciesReferenceImage[];
  similarSpecies: WebSimilarSpecies[];
};

export type SpeciesDictionaryMetadataValues = {
  title: string;
  description: string;
  canonicalPath: string;
  socialImageUrl: string | null;
};

export class SpeciesDictionaryUpstreamError extends Error {
  readonly status: number | null;

  constructor(status: number | null, message = "Species dictionary request failed") {
    super(message);
    this.name = "SpeciesDictionaryUpstreamError";
    this.status = status;
  }
}

export function normalizedSpeciesDictionaryId(value: string): string | null {
  const trimmed = value.trim();
  return UUID_REGEX.test(trimmed) ? trimmed.toLowerCase() : null;
}

export function speciesDictionaryPath(speciesId: string): string | null {
  const normalized = normalizedSpeciesDictionaryId(speciesId);
  return normalized ? `/species/${normalized}` : null;
}

export function speciesDictionarySlug(
  commonName: string | null | undefined,
  scientificName: string | null | undefined,
): string {
  for (const candidate of [commonName, scientificName]) {
    const slug = speciesSlugCandidate(candidate);
    if (slug) return slug;
  }
  return "species";
}

export function canonicalSpeciesDictionaryPath(
  speciesId: string,
  commonName: string | null | undefined,
  scientificName: string | null | undefined,
): string | null {
  const basePath = speciesDictionaryPath(speciesId);
  return basePath
    ? `${basePath}/${speciesDictionarySlug(commonName, scientificName)}`
    : null;
}

export function speciesDictionaryRedirectPath(
  speciesId: string,
  commonName: string | null | undefined,
  scientificName: string | null | undefined,
  requestedSlug: string | undefined,
): string | null {
  const canonicalSlug = speciesDictionarySlug(commonName, scientificName);
  if (requestedSlug === canonicalSlug) return null;
  return canonicalSpeciesDictionaryPath(speciesId, commonName, scientificName);
}

export function nativeSpeciesDictionaryUrl(speciesId: string): string | null {
  const normalized = normalizedSpeciesDictionaryId(speciesId);
  return normalized ? `naturebook://species/${normalized}` : null;
}

export function speciesDictionaryMetadataValues(
  species: WebSpeciesDictionaryEntry,
): SpeciesDictionaryMetadataValues {
  const overview = species.wikipediaOverview?.replace(/\s+/g, " ").trim();
  const prefix = `${species.commonName} (${species.scientificName})`;
  const description = overview
    ? `${prefix}: ${overview}`.slice(0, 160).trimEnd()
    : `${prefix} in the Naturebook Species Dictionary.`;

  return {
    title: species.commonName,
    description,
    canonicalPath: canonicalSpeciesDictionaryPath(
      species.id,
      species.commonName,
      species.scientificName,
    ) ?? `/species/${species.id}/species`,
    socialImageUrl: species.referenceImages[0]?.url ?? null,
  };
}

export async function fetchSpeciesDictionary(
  speciesId: string,
  invoke: SpeciesDictionaryInvoker = invokeSpeciesDictionary,
): Promise<WebSpeciesDictionaryEntry | null> {
  const normalizedId = normalizedSpeciesDictionaryId(speciesId);
  if (!normalizedId) return null;

  const { data, error } = await invoke(normalizedId);
  if (error) {
    const status = functionsErrorStatus(error);
    if (status === 404 && functionsErrorReachedMerianHandler(error)) {
      return null;
    }
    throw new SpeciesDictionaryUpstreamError(status);
  }

  const entry = parseSpeciesDictionaryResponse(data);
  if (entry.id !== normalizedId) {
    throw new SpeciesDictionaryUpstreamError(
      null,
      "Species dictionary returned an unexpected species identity",
    );
  }
  return entry;
}

export function parseSpeciesDictionaryResponse(value: unknown): WebSpeciesDictionaryEntry {
  const response = recordValue(value);
  if (response.schema_version !== 1) {
    throw new SpeciesDictionaryUpstreamError(null, "Unsupported species dictionary schema version");
  }
  const data = recordValue(response.data);
  const id = requiredUUID(data.id, "data.id");
  const scientificName = requiredString(data.scientific_name, "data.scientific_name");
  const commonName = requiredString(data.common_name, "data.common_name");
  const taxonomy = optionalRecordValue(data.taxonomy);

  return {
    id,
    scientificName,
    commonName,
    contentQuality: contentQualityValue(data.content_quality),
    alternativeCommonNames: stringArray(data.alternative_common_names),
    taxonomy: {
      kingdom: optionalString(taxonomy?.kingdom),
      phylum: optionalString(taxonomy?.phylum),
      class: optionalString(taxonomy?.class),
      order: optionalString(taxonomy?.order),
      family: optionalString(taxonomy?.family),
      genus: optionalString(taxonomy?.genus),
    },
    hazardType: optionalString(data.hazard_type),
    iucnRedListStatus: optionalString(data.iucn_red_list_status),
    wikipediaUrl: optionalHTTPSURL(data.wikipedia_url),
    wikipediaOverview: optionalString(data.wikipedia_overview),
    habitatDescription: optionalString(data.habitat_description),
    gbifTaxonKey: positiveInteger(data.gbif_taxon_key),
    groupTags: stringArray(data.group_tags),
    referenceImages: webSafeReferenceImages(data.reference_images),
    similarSpecies: similarSpeciesValues(data.similar_species),
  };
}

export function webSafeReferenceImages(value: unknown): PublicSpeciesReferenceImage[] {
  const images = Array.isArray(value)
    ? value.flatMap((candidate) => {
      const row = optionalRecordValue(candidate);
      if (!row) return [];

      const url = optionalHTTPSURL(row.url);
      const source = referenceImageSource(row.source);
      if (!url || !source) return [];

      const image: PublicSpeciesReferenceImage = { url, source };
      const license = optionalString(row.license);
      const attribution = optionalString(row.attribution);
      const width = positiveInteger(row.width);
      const height = positiveInteger(row.height);
      if (license) image.license = license;
      if (attribution) image.attribution = attribution;
      if (width) image.width = width;
      if (height) image.height = height;
      return [image];
    })
    : [];

  const blockedURLs = new Set(
    publicWebReferenceImageAttributionIssues(images).map((issue) => issue.url),
  );
  return images.filter((image) => !blockedURLs.has(image.url));
}

async function invokeSpeciesDictionary(
  speciesId: string,
): Promise<SpeciesDictionaryInvokerResult> {
  const client = createPublicServerSupabaseClient();
  if (!client) {
    throw new SpeciesDictionaryUpstreamError(
      null,
      "Species dictionary server configuration is unavailable",
    );
  }

  return client.functions.invoke("species-dictionary", {
    body: { species_id: speciesId },
  });
}

function functionsErrorStatus(error: unknown): number | null {
  const errorRecord = optionalRecordValue(error);
  const context = optionalRecordValue(errorRecord?.context);
  const status = context?.status;
  return typeof status === "number" && Number.isInteger(status) ? status : null;
}

function functionsErrorReachedMerianHandler(error: unknown): boolean {
  const errorRecord = optionalRecordValue(error);
  const context = optionalRecordValue(errorRecord?.context);
  const headers = context?.headers;
  if (!headers || typeof headers !== "object") return false;

  const get = (headers as { get?: unknown }).get;
  if (typeof get === "function") {
    const marker = get.call(headers, "X-Merian-Handler");
    return typeof marker === "string" && marker.trim() === "1";
  }

  const headerRecord = optionalRecordValue(headers);
  const marker = headerRecord?.["x-merian-handler"] ??
    headerRecord?.["X-Merian-Handler"];
  return typeof marker === "string" && marker.trim() === "1";
}

function similarSpeciesValues(value: unknown): WebSimilarSpecies[] {
  if (!Array.isArray(value)) return [];

  return value.flatMap((candidate) => {
    const row = optionalRecordValue(candidate);
    const scientificName = optionalString(row?.scientific_name);
    if (!row || !scientificName) return [];

    return [{
      speciesId: typeof row.species_id === "string"
        ? normalizedSpeciesDictionaryId(row.species_id)
        : null,
      scientificName,
      commonName: optionalString(row.common_name),
      iucnRedListStatus: optionalString(row.iucn_red_list_status),
    }];
  });
}

function recordValue(value: unknown): Record<string, unknown> {
  const record = optionalRecordValue(value);
  if (!record) throw new SpeciesDictionaryUpstreamError(null, "Invalid species dictionary response");
  return record;
}

function optionalRecordValue(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function requiredString(value: unknown, field: string): string {
  const result = optionalString(value);
  if (!result) {
    throw new SpeciesDictionaryUpstreamError(null, `Invalid species dictionary ${field}`);
  }
  return result;
}

function requiredUUID(value: unknown, field: string): string {
  const result = typeof value === "string" ? normalizedSpeciesDictionaryId(value) : null;
  if (!result) {
    throw new SpeciesDictionaryUpstreamError(null, `Invalid species dictionary ${field}`);
  }
  return result;
}

function optionalString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.flatMap((candidate) => {
    const string = optionalString(candidate);
    if (!string || seen.has(string.toLowerCase())) return [];
    seen.add(string.toLowerCase());
    return [string];
  });
}

function optionalHTTPSURL(value: unknown): string | null {
  const string = optionalString(value);
  if (!string) return null;

  try {
    const url = new URL(string);
    return url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : null;
}

function contentQualityValue(
  value: unknown,
): WebSpeciesDictionaryEntry["contentQuality"] {
  return value === "complete" || value === "sparse" || value === "needs_enrichment"
    ? value
    : "needs_enrichment";
}

function referenceImageSource(
  value: unknown,
): PublicSpeciesReferenceImage["source"] | null {
  return value === "merian" || value === "wikipedia" || value === "gbif"
    ? value
    : null;
}

function speciesSlugCandidate(value: string | null | undefined): string | null {
  const slug = value
    ?.trim()
    .normalize("NFKD")
    .replace(/\p{M}+/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, SPECIES_SLUG_MAX_LENGTH)
    .replace(/-+$/g, "");
  return slug || null;
}
