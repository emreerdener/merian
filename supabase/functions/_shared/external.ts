/**
 * Fetches English vernacular names for a species from GBIF using a known usageKey.
 * Normalises to Title Case and deduplicates. Returns an empty array on timeout,
 * non-OK response, or no English entries — never throws.
 */
function normalizeVernacularName(name: string): string {
  return name
    .split(" ")
    .map((word: string) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(" ");
}

function collectEnglishVernacularNames(results: unknown): string[] {
  const seen = new Set<string>();
  const names: string[] = [];

  for (const entry of (results as Array<Record<string, unknown>> | undefined) ?? []) {
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

export async function fetchGBIFVernacularNames(gbifKey: number): Promise<string[]> {
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

export async function fetchExternalEnrichment(scientificName: string) {
  let wikiUrl: string | null = null;
  let wikiExtract: string | null = null;
  let gbifKey: number | null = null;
  let combinedImageUrls: string | null = null;
  let wikiTitle: string | null = null;
  let alternativeCommonNames: string[] = [];

  try {
    const fetchedUrls: string[] = [];

    const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
      (async () => {
        let key: number | null = null;
        let urls: string[] = [];
        let vernacularNames: string[] = [];

        const gbifRes = await fetch(
          `https://api.gbif.org/v1/species/match?name=${encodeURIComponent(scientificName)}`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!gbifRes.ok) throw new Error("GBIF match lookup failed");
        const gbifJson = await gbifRes.json();
        key = gbifJson.usageKey || null;

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

          if (vernacularOutcome.status === "fulfilled" && vernacularOutcome.value.ok) {
            const vernacularJson = await vernacularOutcome.value.json();
            vernacularNames = collectEnglishVernacularNames(vernacularJson.results);
          }
        }
        return { key, urls, vernacularNames };
      })(),

      (async () => {
        const wikiRes = await fetch(
          `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(scientificName.replace(/ /g, "_"))}`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!wikiRes.ok) throw new Error("Wikipedia lookup failed");
        const wikiJson = await wikiRes.json();
        const url = wikiJson.content_urls?.desktop?.page || null;
        const extract = wikiJson.extract || null;
        const img =
          wikiJson.originalimage?.source || wikiJson.thumbnail?.source || null;
        const title = wikiJson.title || null;
        return { url, extract, img, title };
      })(),
    ]);

    if (gbifOutcome.status === "fulfilled") {
      gbifKey = gbifOutcome.value.key;
      fetchedUrls.push(...gbifOutcome.value.urls);
      alternativeCommonNames = gbifOutcome.value.vernacularNames;
    }
    if (wikiOutcome.status === "fulfilled") {
      wikiUrl = wikiOutcome.value.url;
      wikiExtract = wikiOutcome.value.extract;
      wikiTitle = wikiOutcome.value.title;
      if (wikiOutcome.value.img) {
        fetchedUrls.unshift(wikiOutcome.value.img);
      }
    }

    if (fetchedUrls.length > 0) {
      combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
    }
  } catch (e) {
    console.error("[external.ts] Unexpected enrichment error:", e instanceof Error ? e.message : String(e));
  }

  return {
    wikipediaUrl: wikiUrl,
    wikiExtract,
    gbifKey,
    referenceImageUrl: combinedImageUrls,
    alternativeCommonNames,
    wikiTitle,
  };
}
