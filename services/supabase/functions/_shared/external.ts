/**
 * Fetches English vernacular names for a species from GBIF using a known usageKey.
 * Normalises to Title Case and deduplicates. Returns an empty array on timeout,
 * non-OK response, or no English entries — never throws.
 */
function normalizeVernacularName(name: string): string {
  return name
    .split(" ")
    .map((word: string) =>
      word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
    )
    .join(" ");
}

function collectEnglishVernacularNames(results: unknown): string[] {
  const seen = new Set<string>();
  const names: string[] = [];

  for (
    const entry of (results as Array<Record<string, unknown>> | undefined) ?? []
  ) {
    const language = entry.language;
    if (language !== "eng" && language !== "en") continue;

    const rawName = typeof entry.vernacularName === "string"
      ? entry.vernacularName.trim()
      : "";
    if (!rawName) continue;

    const normalized = normalizeVernacularName(rawName);
    const dedupeKey = normalized.toLowerCase();
    if (seen.has(dedupeKey)) continue;

    seen.add(dedupeKey);
    names.push(normalized);
  }

  return names;
}

export interface ExternalEnrichmentTaxonomy {
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
}

export interface ExternalEnrichmentData {
  wikipediaUrl: string | null;
  wikiExtract: string | null;
  gbifKey: number | null;
  referenceImageUrl: string | null;
  alternativeCommonNames: string[];
  wikiTitle: string | null;
  gbifTaxonomy: ExternalEnrichmentTaxonomy | null;
}

export async function fetchGBIFVernacularNames(
  gbifKey: number,
): Promise<string[]> {
  try {
    const res = await fetch(
      `https://api.gbif.org/v1/species/${gbifKey}/vernacularNames?limit=30`,
      { signal: AbortSignal.timeout(2500) },
    );
    if (!res.ok) return [];
    const json = await res.json();
    return collectEnglishVernacularNames(json.results);
  } catch {
    return [];
  }
}

interface WikiSummary {
  url: string | null;
  extract: string | null;
  img: string | null;
  title: string | null;
  type: string | null;
}

async function fetchWikiSummary(title: string): Promise<WikiSummary | null> {
  try {
    const wikiRes = await fetch(
      `https://en.wikipedia.org/api/rest_v1/page/summary/${
        encodeURIComponent(title.replace(/ /g, "_"))
      }`,
      { signal: AbortSignal.timeout(2500) },
    );
    if (!wikiRes.ok) return null;
    const wikiJson = await wikiRes.json();
    const url = wikiJson.content_urls?.desktop?.page || null;
    const extract = wikiJson.extract || null;
    const img = wikiJson.originalimage?.source ||
      wikiJson.thumbnail?.source || null;
    const resTitle = wikiJson.title || null;
    const type = wikiJson.type || null;
    return { url, extract, img, title: resTitle, type };
  } catch {
    return null;
  }
}

export async function fetchExternalEnrichment(
  scientificName: string,
): Promise<ExternalEnrichmentData> {
  let wikiUrl: string | null = null;
  let wikiExtract: string | null = null;
  let gbifKey: number | null = null;
  let combinedImageUrls: string | null = null;
  let wikiTitle: string | null = null;
  let alternativeCommonNames: string[] = [];
  let gbifTaxonomy: ExternalEnrichmentTaxonomy | null = null;

  try {
    const fetchedUrls: string[] = [];

    const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
      (async () => {
        let key: number | null = null;
        let urls: string[] = [];
        let vernacularNames: string[] = [];
        let rank: string | null = null;

        const gbifRes = await fetch(
          `https://api.gbif.org/v1/species/match?name=${
            encodeURIComponent(scientificName)
          }`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!gbifRes.ok) throw new Error("GBIF match lookup failed");
        const gbifJson = await gbifRes.json();
        key = gbifJson.usageKey || null;
        const taxonomy = gbifTaxonomyFromMatch(gbifJson);
        rank = stringValue(gbifJson.rank);

        if (key) {
          // Fetch occurrence images and vernacular names in parallel — both depend on key
          // but are independent of each other, so concurrent requests halve the wait time.
          const [mediaOutcome, vernacularOutcome] = await Promise.allSettled([
            fetch(
              `https://api.gbif.org/v1/occurrence/search?taxonKey=${key}&mediaType=StillImage&limit=4`,
              { signal: AbortSignal.timeout(2500) },
            ),
            fetch(
              `https://api.gbif.org/v1/species/${key}/vernacularNames?language=eng&limit=30`,
              { signal: AbortSignal.timeout(2500) },
            ),
          ]);

          if (mediaOutcome.status === "fulfilled" && mediaOutcome.value.ok) {
            const mediaJson = await mediaOutcome.value.json();
            if (mediaJson.results && mediaJson.results.length > 0) {
              const gbifUrls: string[] = [];
              for (const result of mediaJson.results) {
                if (result.media && result.media.length > 0) {
                  for (const m of result.media) {
                    if (m.type === "StillImage" && m.identifier) {
                      gbifUrls.push(m.identifier);
                      break; // take the primary image from each observation
                    }
                  }
                }
              }
              urls = gbifUrls.slice(0, 4);
            }
          }

          if (
            vernacularOutcome.status === "fulfilled" &&
            vernacularOutcome.value.ok
          ) {
            const vernacularJson = await vernacularOutcome.value.json();
            vernacularNames = collectEnglishVernacularNames(
              vernacularJson.results,
            );
          }
        }
        return { key, urls, vernacularNames, taxonomy, rank };
      })(),

      (async () => {
        return await fetchWikiSummary(scientificName);
      })(),
    ]);

    if (gbifOutcome.status === "fulfilled") {
      gbifKey = gbifOutcome.value.key;
      fetchedUrls.push(...gbifOutcome.value.urls);
      alternativeCommonNames = gbifOutcome.value.vernacularNames;
      gbifTaxonomy = gbifOutcome.value.taxonomy;
    }

    let wikiImg: string | null = null;
    if (wikiOutcome.status === "fulfilled" && wikiOutcome.value) {
      let summary = wikiOutcome.value;
      if (summary.type === "disambiguation") {
        const rank = gbifOutcome.status === "fulfilled" ? gbifOutcome.value.rank : null;
        const taxonomy = gbifOutcome.status === "fulfilled" ? gbifOutcome.value.taxonomy : null;

        const suffixSet = new Set<string>();
        if (rank === "GENUS") {
          suffixSet.add("genus");
        }
        if (taxonomy?.kingdom === "Plantae") {
          suffixSet.add("plant");
        }
        if (taxonomy?.kingdom === "Animalia") {
          if (taxonomy?.class === "Insecta") {
            suffixSet.add("insect");
          }
          if (taxonomy?.class === "Aves") {
            suffixSet.add("bird");
          }
          suffixSet.add("animal");
        }
        if (taxonomy?.kingdom === "Fungi") {
          suffixSet.add("fungus");
        }
        // Fallbacks
        suffixSet.add("genus");
        suffixSet.add("plant");
        suffixSet.add("animal");

        for (const suffix of suffixSet) {
          const candidateTitle = `${scientificName} (${suffix})`;
          const candidateSummary = await fetchWikiSummary(candidateTitle);
          if (candidateSummary && candidateSummary.type !== "disambiguation") {
            summary = candidateSummary;
            break;
          }
        }
      }

      if (summary.type !== "disambiguation") {
        wikiUrl = summary.url;
        wikiExtract = summary.extract;
        wikiTitle = summary.title;
        wikiImg = summary.img;
      } else {
        wikiUrl = summary.url;
        wikiTitle = summary.title;
      }
    }

    if (wikiImg) {
      fetchedUrls.unshift(wikiImg);
    }

    if (fetchedUrls.length > 0) {
      combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
    }
  } catch (e) {
    console.error(
      "[external.ts] Unexpected enrichment error:",
      e instanceof Error ? e.message : String(e),
    );
  }

  return {
    wikipediaUrl: wikiUrl,
    wikiExtract,
    gbifKey,
    referenceImageUrl: combinedImageUrls,
    alternativeCommonNames,
    wikiTitle,
    gbifTaxonomy,
  };
}

function gbifTaxonomyFromMatch(
  value: Record<string, unknown>,
): ExternalEnrichmentTaxonomy | null {
  const taxonomy: ExternalEnrichmentTaxonomy = {
    kingdom: stringValue(value.kingdom),
    phylum: stringValue(value.phylum),
    class: stringValue(value.class),
    order: stringValue(value.order),
    family: stringValue(value.family),
    genus: stringValue(value.genus),
  };

  return Object.values(taxonomy).some((entry) => entry != null)
    ? taxonomy
    : null;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
