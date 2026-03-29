export async function fetchExternalEnrichment(scientificName: string) {
  let wikiUrl: string | null = null;
  let wikiExtract: string | null = null;
  let gbifKey: number | null = null;
  let combinedImageUrls: string | null = null;

  try {
    const fetchedUrls: string[] = [];

    const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
      (async () => {
        let key: number | null = null;
        let urls: string[] = [];
        const gbifRes = await fetch(
          `https://api.gbif.org/v1/species/match?name=${encodeURIComponent(scientificName)}`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!gbifRes.ok) throw new Error("GBIF match lookup failed");
        const gbifJson = await gbifRes.json();
        key = gbifJson.usageKey || null;

        if (key) {
          const mediaRes = await fetch(
            `https://api.gbif.org/v1/occurrence/search?taxonKey=${key}&mediaType=StillImage&limit=4`,
            { signal: AbortSignal.timeout(2500) },
          );
          if (mediaRes.ok) {
            const mediaJson = await mediaRes.json();
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
        }
        return { key, urls };
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
        return { url, extract, img };
      })(),
    ]);

    if (gbifOutcome.status === "fulfilled") {
      gbifKey = gbifOutcome.value.key;
      fetchedUrls.push(...gbifOutcome.value.urls);
    }
    if (wikiOutcome.status === "fulfilled") {
      wikiUrl = wikiOutcome.value.url;
      wikiExtract = wikiOutcome.value.extract;
      if (wikiOutcome.value.img) {
        fetchedUrls.unshift(wikiOutcome.value.img);
      }
    }

    if (fetchedUrls.length > 0) {
      combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
    }
  } catch (e) {
    console.log("Data enrichment failed silently: ", e);
  }

  return {
    wikipediaUrl: wikiUrl,
    wikiExtract,
    gbifKey,
    referenceImageUrl: combinedImageUrls,
  };
}
