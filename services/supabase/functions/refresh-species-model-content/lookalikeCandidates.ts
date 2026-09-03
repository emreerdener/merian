import type { SimilarSpeciesEntry } from "../_shared/biology.ts";
import {
  fetchWithDeadline,
  readResponseJsonWithinLimit,
} from "../_shared/outbound.ts";
import {
  normalizePublicConfidence,
  sanitizeLookalikeVisualTraits,
  stringValue,
} from "../_shared/publicSpeciesProjection.ts";

export const MAX_LOOKALIKE_CANDIDATES = 3;
const GBIF_TIMEOUT_MS = 6_000;
const GBIF_RESPONSE_BYTES = 64 * 1024;
const TAXONOMY_PLACEHOLDERS = new Set([
  "unknown",
  "unavailable",
  "not available",
  "n/a",
  "none",
  "null",
  "undefined",
]);

export interface LookalikeTaxonomy {
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
}

export interface VerifiedLookalikeTaxon extends LookalikeTaxonomy {
  scientific_name: string;
  gbif_taxon_key: number;
  rank: "SPECIES";
  status: "ACCEPTED";
}

export interface PreparedLookalikeCandidate {
  scientific_name: string;
  common_name: string | null;
  reason: string | null;
  visual_traits: string[];
  confidence: number | null;
  gbif: VerifiedLookalikeTaxon;
}

export interface PreparedLookalikeCandidates {
  candidates: PreparedLookalikeCandidate[];
  unresolvedCount: number;
  rejectedCount: number;
}

export type LookalikeTaxonFetcher = (
  scientificName: string,
  primary: LookalikeTaxonomy,
) => Promise<VerifiedLookalikeTaxon | null>;

export function normalizeLookalikeCandidates(
  entries: SimilarSpeciesEntry[],
): SimilarSpeciesEntry[] {
  const seen = new Set<string>();
  return entries.slice(0, MAX_LOOKALIKE_CANDIDATES).flatMap((entry) => {
    const scientificName = text(entry?.scientific_name);
    if (!scientificName || scientificName.length > 160) {
      throw new Error("Lookalike generation returned an invalid species name.");
    }
    const key = scientificName.toLowerCase();
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ ...entry, scientific_name: scientificName }];
  });
}

export async function prepareLookalikeCandidates(
  primaryName: string,
  primary: LookalikeTaxonomy,
  entries: SimilarSpeciesEntry[],
  fetchTaxon: LookalikeTaxonFetcher = fetchVerifiedLookalikeTaxon,
): Promise<PreparedLookalikeCandidates> {
  const result: PreparedLookalikeCandidates = {
    candidates: [],
    unresolvedCount: 0,
    rejectedCount: 0,
  };
  const seen = new Set<string>([text(primaryName)?.toLowerCase() ?? ""]);

  // Sequential, bounded resolution keeps provider concurrency at the worker's
  // existing cap. A failed lookup does not discard other usable candidates.
  for (const entry of normalizeLookalikeCandidates(entries)) {
    const key = entry.scientific_name.toLowerCase();
    if (seen.has(key)) {
      result.rejectedCount += 1;
      continue;
    }
    let taxon: VerifiedLookalikeTaxon | null;
    try {
      taxon = await fetchTaxon(entry.scientific_name, primary);
    } catch {
      result.unresolvedCount += 1;
      continue;
    }
    if (!taxon) {
      result.unresolvedCount += 1;
      continue;
    }
    const validated = lookalikeTaxonomyCompatibility(primary, taxon);
    if (validated !== "compatible") {
      result[
        validated === "incomplete" ? "unresolvedCount" : "rejectedCount"
      ] += 1;
      continue;
    }
    const canonicalKey = taxon.scientific_name.toLowerCase();
    if (seen.has(canonicalKey)) {
      result.rejectedCount += 1;
      continue;
    }
    seen.add(canonicalKey);
    result.candidates.push({
      scientific_name: taxon.scientific_name,
      common_name: text(entry.common_name)?.slice(0, 160) ?? null,
      reason: stringValue(entry.reason)?.slice(0, 500) ?? null,
      visual_traits: sanitizeLookalikeVisualTraits(entry.visual_traits),
      confidence: normalizePublicConfidence(entry.confidence),
      gbif: taxon,
    });
  }
  return result;
}

export function lookalikeTaxonomyCompatibility(
  primary: LookalikeTaxonomy,
  candidate: LookalikeTaxonomy,
): "compatible" | "incompatible" | "incomplete" {
  const primaryKingdom = rank(primary.kingdom);
  const candidateKingdom = rank(candidate.kingdom);
  if (!primaryKingdom || !candidateKingdom) return "incomplete";
  if (primaryKingdom !== candidateKingdom) return "incompatible";
  const primaryOrder = rank(primary.order);
  const primaryFamily = rank(primary.family);
  if (!primaryOrder && !primaryFamily) return "incomplete";
  const candidateRank = rank(primaryOrder ? candidate.order : candidate.family);
  if (!candidateRank) return "incomplete";
  return candidateRank === (primaryOrder ?? primaryFamily)
    ? "compatible"
    : "incompatible";
}

export async function fetchVerifiedLookalikeTaxon(
  scientificName: string,
  primary: LookalikeTaxonomy,
  fetcher: typeof fetch = fetch,
): Promise<VerifiedLookalikeTaxon | null> {
  const url = new URL("https://api.gbif.org/v1/species/match");
  url.searchParams.set("name", scientificName);
  url.searchParams.set("strict", "true");
  url.searchParams.set("rank", "SPECIES");
  for (const key of ["kingdom", "order", "family"] as const) {
    if (rank(primary[key])) url.searchParams.set(key, text(primary[key])!);
  }
  const match = await fetchGbifObject(url, fetcher);
  if (
    match.matchType !== "EXACT" || match.rank !== "SPECIES" ||
    text(match.canonicalName)?.toLowerCase() !== scientificName.toLowerCase()
  ) return null;

  let accepted = match;
  let taxonKey = positiveKey(match.usageKey);
  if (match.status === "SYNONYM") {
    taxonKey = positiveKey(match.acceptedUsageKey);
    if (!taxonKey) return null;
    accepted = await fetchGbifObject(
      new URL(`https://api.gbif.org/v1/species/${taxonKey}`),
      fetcher,
    );
    if (positiveKey(accepted.key) !== taxonKey) return null;
  }
  const canonicalName = text(accepted.canonicalName);
  if (
    !taxonKey || !canonicalName || canonicalName.length > 160 ||
    accepted.rank !== "SPECIES" ||
    (accepted.taxonomicStatus ?? accepted.status) !== "ACCEPTED"
  ) return null;
  return {
    scientific_name: canonicalName,
    gbif_taxon_key: taxonKey,
    rank: "SPECIES",
    status: "ACCEPTED",
    kingdom: text(accepted.kingdom),
    phylum: text(accepted.phylum),
    class: text(accepted.class),
    order: text(accepted.order),
    family: text(accepted.family),
    genus: text(accepted.genus),
  };
}

async function fetchGbifObject(
  url: URL,
  fetcher: typeof fetch,
): Promise<Record<string, unknown>> {
  const response = await fetchWithDeadline(
    url,
    { headers: { Accept: "application/json" } },
    { fetcher, timeoutMs: GBIF_TIMEOUT_MS },
  );
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(
      `GBIF lookalike resolution failed with HTTP ${response.status}.`,
    );
  }
  const value = await readResponseJsonWithinLimit(
    response,
    GBIF_RESPONSE_BYTES,
  );
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("GBIF lookalike resolution returned an invalid response.");
  }
  return value as Record<string, unknown>;
}

function positiveKey(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value > 0 && value <= 2147483647
    ? value
    : null;
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  return value.trim().replace(/\s+/g, " ") || null;
}

function rank(value: unknown): string | null {
  const normalized = text(value)?.toLowerCase();
  return normalized && !TAXONOMY_PLACEHOLDERS.has(normalized)
    ? normalized
    : null;
}
