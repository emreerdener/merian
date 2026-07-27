import {
  fetchWithDeadline,
  readResponseJsonWithinLimit,
} from "../_shared/outbound.ts";

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

type Fetcher = typeof fetch;
const GBIF_SUGGEST_REQUEST_TIMEOUT_MS = 2_500;
const GBIF_SUGGEST_RESPONSE_LIMIT_BYTES = 256 * 1024;

const ACCEPTED_RANKS = new Set([
  "kingdom",
  "phylum",
  "class",
  "order",
  "family",
  "genus",
  "species",
]);

export function shouldFetchGbifCommunityTaxa(
  query: string,
  localResultCount: number,
  limit: number,
): boolean {
  return query.trim().length >= 3 &&
    localResultCount < Math.min(Math.max(limit, 1), 5);
}

export async function fetchGbifCommunityTaxa(
  query: string,
  limit: number,
  fetcher: Fetcher = fetch,
): Promise<GbifCommunityTaxon[]> {
  const cappedLimit = Math.min(Math.max(limit, 1), 20);
  const url = new URL("https://api.gbif.org/v1/species/suggest");
  url.searchParams.set("q", query);
  url.searchParams.set("limit", String(cappedLimit));

  const response = await fetchWithDeadline(
    url,
    { headers: { "Accept": "application/json" } },
    { fetcher, timeoutMs: GBIF_SUGGEST_REQUEST_TIMEOUT_MS },
  );
  if (!response.ok) {
    await response.body?.cancel().catch(() => undefined);
    return [];
  }

  const json = await readResponseJsonWithinLimit(
    response,
    GBIF_SUGGEST_RESPONSE_LIMIT_BYTES,
  );
  if (!Array.isArray(json)) return [];

  const taxa: GbifCommunityTaxon[] = [];
  const seen = new Set<number>();
  for (const entry of json) {
    const taxon = normalizeGbifSuggestEntry(entry);
    if (!taxon || seen.has(taxon.gbif_taxon_key)) continue;
    seen.add(taxon.gbif_taxon_key);
    taxa.push(taxon);
  }
  return taxa;
}

export function normalizeGbifSuggestEntry(
  entry: unknown,
): GbifCommunityTaxon | null {
  if (!entry || typeof entry !== "object") return null;
  const row = entry as Record<string, unknown>;
  const gbifKey = positiveInteger(row.key ?? row.usageKey);
  if (gbifKey == null) return null;

  const rank = stringValue(row.rank)?.toLowerCase() ?? "species";
  if (!ACCEPTED_RANKS.has(rank)) return null;

  const scientificName = stringValue(row.canonicalName) ??
    stringValue(row.scientificName);
  if (!scientificName) return null;

  return {
    gbif_taxon_key: gbifKey,
    accepted_gbif_taxon_key: positiveInteger(row.acceptedKey),
    taxonomic_status: stringValue(row.status)?.toLowerCase() ?? null,
    rank,
    scientific_name: scientificName,
    common_name: stringValue(row.vernacularName),
    kingdom: stringValue(row.kingdom),
    phylum: stringValue(row.phylum),
    class: stringValue(row.class),
    order: stringValue(row.order),
    family: stringValue(row.family),
    genus: stringValue(row.genus) ??
      (rank === "genus" ? scientificName : null),
    species: stringValue(row.species) ??
      (rank === "species" ? scientificName : null),
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
