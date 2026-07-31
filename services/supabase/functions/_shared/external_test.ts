import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  fetchExternalEnrichment,
  fetchGBIFCountryOccurrences,
} from "./external.ts";

const jsonResponse = (value: unknown) =>
  new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" },
  });

function enrichmentFixture(options: {
  match: Record<string, unknown>;
  wiki: Record<string, Record<string, unknown>>;
}): typeof fetch {
  return (input) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("/species/match")) {
      return Promise.resolve(jsonResponse(options.match));
    }
    if (url.pathname.endsWith("/occurrence/search")) {
      return Promise.resolve(jsonResponse({ results: [] }));
    }
    if (url.pathname.endsWith("/vernacularNames")) {
      return Promise.resolve(jsonResponse({ results: [] }));
    }
    const summaryPrefix = "/api/rest_v1/page/summary/";
    if (url.pathname.startsWith(summaryPrefix)) {
      const title = decodeURIComponent(url.pathname.slice(summaryPrefix.length))
        .replaceAll("_", " ");
      const fixture = options.wiki[title];
      return Promise.resolve(
        fixture ? jsonResponse(fixture) : new Response(null, { status: 404 }),
      );
    }
    return Promise.resolve(new Response(null, { status: 404 }));
  };
}

Deno.test("fetchGBIFCountryOccurrences normalizes the bounded GBIF country facet", async () => {
  const request: { url?: URL; userAgent?: string | null } = {};
  const fetcher: typeof fetch = (input, init) => {
    const requestInit = init as { headers?: HeadersInit } | undefined;
    request.url = new URL(String(input));
    request.userAgent = new Headers(requestInit?.headers).get("user-agent");
    return Promise.resolve(jsonResponse({
      facets: [
        {
          field: "COUNTRY",
          counts: [
            { name: "us", count: 128 },
            { name: "CA", count: 42 },
            { name: "US", count: 120 },
          ],
        },
      ],
    }));
  };

  const result = await fetchGBIFCountryOccurrences(5139790, fetcher);

  assertEquals(result, [
    { countryCode: "CA", occurrenceCount: 42 },
    { countryCode: "US", occurrenceCount: 128 },
  ]);
  assertEquals(request.url?.searchParams.get("taxonKey"), "5139790");
  assertEquals(request.url?.searchParams.get("occurrenceStatus"), "PRESENT");
  assertEquals(request.url?.searchParams.get("hasCoordinate"), "true");
  assertEquals(request.url?.searchParams.get("hasGeospatialIssue"), "false");
  assertEquals(request.url?.searchParams.get("limit"), "0");
  assertEquals(request.url?.searchParams.get("facet"), "country");
  assertEquals(request.url?.searchParams.get("facetLimit"), "300");
  assertEquals(request.userAgent?.startsWith("Naturebook "), true);
});

Deno.test("fetchGBIFCountryOccurrences distinguishes empty coverage from provider failure", async () => {
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () => Promise.resolve(jsonResponse({ facets: [] })),
    ),
    [],
  );
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () =>
        Promise.resolve(jsonResponse({
          facets: [{ field: "COUNTRY", counts: [] }],
        })),
    ),
    [],
  );
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () => Promise.resolve(new Response(null, { status: 503 })),
    ),
    null,
  );
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () => Promise.resolve(jsonResponse({ results: [] })),
    ),
    null,
  );
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () =>
        Promise.resolve(jsonResponse({
          facets: [{ field: "COUNTRY" }],
        })),
    ),
    null,
  );
  assertEquals(
    await fetchGBIFCountryOccurrences(
      123,
      () =>
        Promise.resolve(jsonResponse({
          facets: [{
            field: "COUNTRY",
            counts: [{ name: "not-a-country", count: 50 }],
          }],
        })),
    ),
    null,
  );
});

Deno.test("fetchExternalEnrichment distinguishes an unmatched name from an unavailable GBIF match", async () => {
  const unmatched = await fetchExternalEnrichment(
    "Regionalis absentis",
    enrichmentFixture({
      match: { matchType: "NONE", confidence: 100 },
      wiki: {},
    }),
  );
  assertEquals(unmatched.gbifMatchStatus, "unmatched");

  const unavailable = await fetchExternalEnrichment(
    "Regionalis interrupta",
    (input) => {
      const url = String(input);
      return Promise.resolve(
        url.includes("/species/match")
          ? new Response(null, { status: 503 })
          : new Response(null, { status: 404 }),
      );
    },
  );
  assertEquals(unavailable.gbifMatchStatus, "unavailable");
});

Deno.test("fetchExternalEnrichment suppresses denied media and promotes the next result", async () => {
  const blocked =
    "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/medium.jpg?size=500";
  const safe =
    "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg";
  const fetcher: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("/species/match")) {
      return Promise.resolve(jsonResponse({
        usageKey: 123,
        rank: "SPECIES",
        kingdom: "Animalia",
        class: "Mammalia",
      }));
    }
    if (url.includes("/occurrence/search")) {
      return Promise.resolve(jsonResponse({
        results: [
          { media: [{ type: "StillImage", identifier: blocked }] },
          { media: [{ type: "StillImage", identifier: safe }] },
        ],
      }));
    }
    if (url.includes("/vernacularNames")) {
      return Promise.resolve(jsonResponse({ results: [] }));
    }
    if (url.includes("en.wikipedia.org")) {
      return Promise.resolve(jsonResponse({
        title: "European wildcat",
        type: "standard",
        extract: "A wildcat.",
        originalimage: { source: blocked },
        content_urls: {
          desktop: { page: "https://en.wikipedia.org/wiki/European_wildcat" },
        },
      }));
    }
    return Promise.resolve(new Response(null, { status: 404 }));
  };

  const result = await fetchExternalEnrichment("Felis silvestris", fetcher);

  assertEquals(result.referenceImageUrl, safe);
});

Deno.test("fetchExternalEnrichment isolates oversized media from valid taxonomy and names", async () => {
  const oversizedMedia = new Uint8Array(256 * 1024 + 1);
  const fetcher: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("/species/match")) {
      return Promise.resolve(jsonResponse({
        usageKey: 123,
        rank: "SPECIES",
        kingdom: "Animalia",
        class: "Aves",
      }));
    }
    if (url.includes("/occurrence/search")) {
      return Promise.resolve(
        new Response(oversizedMedia, {
          headers: { "content-type": "application/json" },
        }),
      );
    }
    if (url.includes("/vernacularNames")) {
      return Promise.resolve(jsonResponse({
        results: [{ language: "eng", vernacularName: "test bird" }],
      }));
    }
    return Promise.resolve(new Response(null, { status: 404 }));
  };

  const result = await fetchExternalEnrichment("Avis probata", fetcher);

  assertEquals(result.gbifKey, 123);
  assertEquals(result.gbifTaxonomy?.class, "Aves");
  assertEquals(result.alternativeCommonNames, ["Test Bird"]);
  assertEquals(result.referenceImageUrl, null);
});

Deno.test("fetchExternalEnrichment resolves disambiguation for Rosa to standard description", async () => {
  const result = await fetchExternalEnrichment(
    "Rosa",
    enrichmentFixture({
      match: {
        usageKey: 7462843,
        rank: "GENUS",
        kingdom: "Plantae",
      },
      wiki: {
        Rosa: {
          title: "Rosa",
          type: "disambiguation",
          extract: "Rosa may refer to several topics.",
          content_urls: {
            desktop: { page: "https://en.wikipedia.org/wiki/Rosa" },
          },
        },
        "Rosa (plant)": {
          title: "Rose",
          type: "standard",
          extract:
            "A rose is a woody perennial flowering plant of the genus Rosa.",
          content_urls: {
            desktop: { page: "https://en.wikipedia.org/wiki/Rose" },
          },
        },
      },
    }),
  );

  assertNotEquals(result.wikipediaUrl, null);
  assertNotEquals(result.wikiExtract, null);

  // It should NOT contain "refer to" which is typical for a disambiguation page.
  assertEquals(result.wikiExtract?.includes("refer to"), false);

  // It should resolve to the plant/rose details.
  // Rosa (plant) redirects to Rose on Wikipedia
  assertEquals(result.wikiTitle, "Rose");
  assertEquals(
    result.wikiExtract?.includes("woody perennial flowering plant"),
    true,
  );
});

Deno.test("fetchExternalEnrichment resolves standard non-disambiguation species correctly", async () => {
  const result = await fetchExternalEnrichment(
    "Panthera leo",
    enrichmentFixture({
      match: {
        usageKey: 5219404,
        rank: "SPECIES",
        kingdom: "Animalia",
        class: "Mammalia",
      },
      wiki: {
        "Panthera leo": {
          title: "Lion",
          type: "standard",
          extract: "The lion is a large cat of the genus Panthera.",
          content_urls: {
            desktop: { page: "https://en.wikipedia.org/wiki/Lion" },
          },
        },
      },
    }),
  );

  assertNotEquals(result.wikipediaUrl, null);
  assertNotEquals(result.wikiExtract, null);
  assertEquals(result.wikiTitle, "Lion");
  assertEquals(
    result.wikiExtract?.includes("large cat of the genus Panthera"),
    true,
  );
});
