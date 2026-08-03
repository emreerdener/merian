import {
  fetchWithDeadline,
  readResponseJsonWithinLimit,
} from "../_shared/outbound.ts";

export const GBIF_BIRDS_TAXON_KEY = 212;
export const GBIF_BIRDS_SCIENTIFIC_NAME = "Aves";
const GBIF_IMPORT_REQUEST_TIMEOUT_MS = 6_000;
const GBIF_IMPORT_RESPONSE_LIMIT_BYTES = 4 * 1024 * 1024;
const GBIF_IMPORT_MAXIMUM_ATTEMPTS = 3;
const GBIF_IMPORT_INITIAL_RETRY_DELAY_MS = 500;
const GBIF_IMPORT_MAXIMUM_RETRY_DELAY_MS = 2_000;

export interface GbifTaxonomyImportTarget {
  slug: "birds";
  displayName: "Birds";
  rootRank: "class";
  rootScientificName: "Aves";
  rootGbifTaxonKey: number;
}

export const GBIF_IMPORT_TARGETS: Record<
  GbifTaxonomyImportTarget["slug"],
  GbifTaxonomyImportTarget
> = {
  birds: {
    slug: "birds",
    displayName: "Birds",
    rootRank: "class",
    rootScientificName: GBIF_BIRDS_SCIENTIFIC_NAME,
    rootGbifTaxonKey: GBIF_BIRDS_TAXON_KEY,
  },
};

export interface GbifCommunityTaxon {
  gbif_taxon_key: number;
  accepted_gbif_taxon_key: number | null;
  taxonomic_status: string | null;
  rank: string;
  scientific_name: string;
  common_name: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  species: string | null;
  kingdom_gbif_taxon_key: number | null;
  phylum_gbif_taxon_key: number | null;
  class_gbif_taxon_key: number | null;
  order_gbif_taxon_key: number | null;
  family_gbif_taxon_key: number | null;
  genus_gbif_taxon_key: number | null;
}

export interface GbifTaxonomyImportPage {
  offset: number;
  limit: number;
  count: number | null;
  endOfRecords: boolean;
  taxa: GbifCommunityTaxon[];
  rawResultCount: number;
}

type Fetcher = typeof fetch;

export interface GbifTaxonomyImportRetry {
  attempt: number;
  maximumAttempts: number;
  delayMs: number;
  reason: string;
}

export interface GbifTaxonomyImportFetchOptions {
  maximumAttempts?: number;
  wait?: (milliseconds: number) => Promise<void>;
  onRetry?: (retry: GbifTaxonomyImportRetry) => void;
}

export async function fetchGbifTaxonomyImportPage(
  target: GbifTaxonomyImportTarget,
  offset: number,
  limit: number,
  fetcher: Fetcher = fetch,
  options: GbifTaxonomyImportFetchOptions = {},
): Promise<GbifTaxonomyImportPage> {
  const url = new URL("https://api.gbif.org/v1/species/search");
  url.searchParams.set("highertaxon_key", String(target.rootGbifTaxonKey));
  url.searchParams.set("rank", "SPECIES");
  url.searchParams.set("status", "ACCEPTED");
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("limit", String(limit));

  const maximumAttempts = options.maximumAttempts ??
    GBIF_IMPORT_MAXIMUM_ATTEMPTS;
  if (
    !Number.isSafeInteger(maximumAttempts) || maximumAttempts < 1 ||
    maximumAttempts > GBIF_IMPORT_MAXIMUM_ATTEMPTS
  ) {
    throw new TypeError(
      `maximumAttempts must be between 1 and ${GBIF_IMPORT_MAXIMUM_ATTEMPTS}.`,
    );
  }

  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    let response: Response;
    try {
      response = await fetchWithDeadline(
        url,
        { headers: { "Accept": "application/json" } },
        { fetcher, timeoutMs: GBIF_IMPORT_REQUEST_TIMEOUT_MS },
      );
    } catch (error) {
      if (attempt === maximumAttempts) {
        throw new Error(
          `GBIF species search transport failed after ${maximumAttempts} attempts.`,
          { cause: error },
        );
      }
      await waitForGbifRetry(
        attempt,
        maximumAttempts,
        null,
        "transport_error",
        target,
        offset,
        options,
      );
      continue;
    }

    if (!response.ok) {
      const status = response.status;
      const retryable = isRetryableGbifStatus(status);
      if (retryable && attempt < maximumAttempts) {
        const retryDelayMs = gbifRetryDelayMilliseconds(attempt, response);
        await cancelGbifResponseBody(response);
        await waitForGbifRetry(
          attempt,
          maximumAttempts,
          retryDelayMs,
          `http_${status}`,
          target,
          offset,
          options,
        );
        continue;
      }
      await cancelGbifResponseBody(response);
      throw new Error(
        retryable
          ? `GBIF species search failed after ${maximumAttempts} attempts with HTTP ${status}.`
          : `GBIF species search failed with HTTP ${status}.`,
      );
    }

    const json = await readResponseJsonWithinLimit(
      response,
      GBIF_IMPORT_RESPONSE_LIMIT_BYTES,
    );
    if (!json || typeof json !== "object" || Array.isArray(json)) {
      throw new Error("GBIF species search returned an invalid response.");
    }

    return normalizeGbifTaxonomyImportPage(json, offset, limit);
  }

  throw new Error("GBIF species search retry loop ended unexpectedly.");
}

function isRetryableGbifStatus(status: number): boolean {
  return status === 408 || status === 425 || status === 429 ||
    (status >= 500 && status <= 599);
}

async function cancelGbifResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel("GBIF response will not be consumed.");
  } catch {
    // Status and headers are sufficient for retry classification.
  }
}

function gbifRetryDelayMilliseconds(
  attempt: number,
  response: Response | null,
): number {
  const exponentialDelay = Math.min(
    GBIF_IMPORT_INITIAL_RETRY_DELAY_MS * (2 ** (attempt - 1)),
    GBIF_IMPORT_MAXIMUM_RETRY_DELAY_MS,
  );
  const retryAfterValue = response?.headers.get("Retry-After")?.trim() ?? "";
  const retryAfterSeconds = /^(0|[1-9][0-9]*)$/.test(retryAfterValue)
    ? Number(retryAfterValue)
    : 0;
  const retryAfterDelay = Number.isSafeInteger(retryAfterSeconds)
    ? Math.min(
      retryAfterSeconds * 1_000,
      GBIF_IMPORT_MAXIMUM_RETRY_DELAY_MS,
    )
    : 0;
  return Math.max(exponentialDelay, retryAfterDelay);
}

async function waitForGbifRetry(
  attempt: number,
  maximumAttempts: number,
  retryDelayMs: number | null,
  reason: string,
  target: GbifTaxonomyImportTarget,
  offset: number,
  options: GbifTaxonomyImportFetchOptions,
): Promise<void> {
  const delayMs = retryDelayMs ?? gbifRetryDelayMilliseconds(attempt, null);
  const retry = { attempt, maximumAttempts, delayMs, reason };
  if (options.onRetry) {
    options.onRetry(retry);
  } else {
    console.warn(JSON.stringify({
      event: "gbif_taxonomy_import_fetch_retry",
      target: target.slug,
      offset,
      ...retry,
    }));
  }
  const wait = options.wait ??
    ((milliseconds: number) =>
      new Promise<void>((resolve) => setTimeout(resolve, milliseconds)));
  await wait(delayMs);
}

export function normalizeGbifTaxonomyImportPage(
  page: unknown,
  fallbackOffset: number,
  fallbackLimit: number,
): GbifTaxonomyImportPage {
  if (!page || typeof page !== "object" || Array.isArray(page)) {
    return {
      offset: fallbackOffset,
      limit: fallbackLimit,
      count: null,
      endOfRecords: true,
      taxa: [],
      rawResultCount: 0,
    };
  }

  const row = page as Record<string, unknown>;
  const results = Array.isArray(row.results) ? row.results : [];
  const seen = new Set<number>();
  const taxa: GbifCommunityTaxon[] = [];

  for (const result of results) {
    const taxon = normalizeGbifSpeciesSearchResult(result);
    if (!taxon || seen.has(taxon.gbif_taxon_key)) continue;
    seen.add(taxon.gbif_taxon_key);
    taxa.push(taxon);
  }

  return {
    offset: positiveIntegerOrZero(row.offset) ?? fallbackOffset,
    limit: positiveInteger(row.limit) ?? fallbackLimit,
    count: positiveIntegerOrZero(row.count),
    endOfRecords: booleanValue(row.endOfRecords) ?? taxa.length < fallbackLimit,
    taxa,
    rawResultCount: results.length,
  };
}

export function normalizeGbifSpeciesSearchResult(
  entry: unknown,
): GbifCommunityTaxon | null {
  if (!entry || typeof entry !== "object") return null;
  const row = entry as Record<string, unknown>;
  const gbifKey = positiveInteger(row.key ?? row.usageKey ?? row.nubKey);
  if (gbifKey == null) return null;

  const rank = stringValue(row.rank)?.toLowerCase() ?? "species";
  if (rank !== "species") return null;

  const scientificName = stringValue(row.canonicalName) ??
    stringValue(row.scientificName);
  if (!scientificName) return null;

  const acceptedKey = positiveInteger(row.acceptedKey) ?? gbifKey;
  const genus = stringValue(row.genus);

  return {
    gbif_taxon_key: gbifKey,
    accepted_gbif_taxon_key: acceptedKey,
    taxonomic_status: stringValue(row.taxonomicStatus ?? row.status)
      ?.toLowerCase() ?? "accepted",
    rank,
    scientific_name: scientificName,
    common_name: stringValue(row.vernacularName),
    kingdom: stringValue(row.kingdom),
    phylum: stringValue(row.phylum),
    class: stringValue(row.class),
    order: stringValue(row.order),
    family: stringValue(row.family),
    genus,
    species: stringValue(row.species) ?? scientificName,
    kingdom_gbif_taxon_key: positiveInteger(row.kingdomKey),
    phylum_gbif_taxon_key: positiveInteger(row.phylumKey),
    class_gbif_taxon_key: positiveInteger(row.classKey),
    order_gbif_taxon_key: positiveInteger(row.orderKey),
    family_gbif_taxon_key: positiveInteger(row.familyKey),
    genus_gbif_taxon_key: positiveInteger(row.genusKey),
  };
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed.length > 0 ? trimmed : null;
}

function positiveInteger(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    return null;
  }
  return value;
}

function positiveIntegerOrZero(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }
  return value;
}

function booleanValue(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}
