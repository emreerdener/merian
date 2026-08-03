import { assertEquals, assertRejects } from "@std/assert";
import {
  fetchGbifTaxonomyImportPage,
  GBIF_IMPORT_TARGETS,
  normalizeGbifSpeciesSearchResult,
  normalizeGbifTaxonomyImportPage,
} from "./gbif.ts";

Deno.test("GBIF taxonomy import - normalizes accepted species search rows", () => {
  const taxon = normalizeGbifSpeciesSearchResult({
    key: 2492321,
    acceptedKey: 2492321,
    rank: "SPECIES",
    canonicalName: "Setophaga petechia",
    scientificName: "Setophaga petechia (Linnaeus, 1766)",
    taxonomicStatus: "ACCEPTED",
    kingdom: "Animalia",
    phylum: "Chordata",
    class: "Aves",
    order: "Passeriformes",
    family: "Parulidae",
    genus: "Setophaga",
    species: "Setophaga petechia",
    kingdomKey: 1,
    phylumKey: 44,
    classKey: 212,
    orderKey: 729,
    familyKey: 9608,
    genusKey: 2492311,
  });

  assertEquals(taxon?.gbif_taxon_key, 2492321);
  assertEquals(taxon?.rank, "species");
  assertEquals(taxon?.scientific_name, "Setophaga petechia");
  assertEquals(taxon?.class, "Aves");
  assertEquals(taxon?.class_gbif_taxon_key, 212);
});

Deno.test("GBIF taxonomy import - filters unsupported and duplicate page rows", () => {
  const page = normalizeGbifTaxonomyImportPage(
    {
      offset: 0,
      limit: 3,
      count: 100,
      endOfRecords: false,
      results: [
        { key: 1, rank: "SPECIES", canonicalName: "A", class: "Aves" },
        { key: 1, rank: "SPECIES", canonicalName: "A", class: "Aves" },
        { key: 2, rank: "GENUS", canonicalName: "B", class: "Aves" },
      ],
    },
    0,
    3,
  );

  assertEquals(page.rawResultCount, 3);
  assertEquals(page.taxa.length, 1);
  assertEquals(page.endOfRecords, false);
});

Deno.test("GBIF taxonomy import - fetches species search pages with bounded params", async () => {
  const requestedUrls: string[] = [];
  const fetcher = (input: URL | Request | string) => {
    requestedUrls.push(String(input));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          offset: 25,
          limit: 25,
          count: 50,
          endOfRecords: true,
          results: [
            {
              key: 2492321,
              rank: "SPECIES",
              canonicalName: "Setophaga petechia",
              class: "Aves",
              classKey: 212,
            },
          ],
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      ),
    );
  };

  const page = await fetchGbifTaxonomyImportPage(
    GBIF_IMPORT_TARGETS.birds,
    25,
    25,
    fetcher as typeof fetch,
  );

  assertEquals(page.offset, 25);
  assertEquals(page.limit, 25);
  assertEquals(page.taxa.length, 1);
  const url = new URL(requestedUrls[0]);
  assertEquals(url.pathname, "/v1/species/search");
  assertEquals(url.searchParams.get("highertaxon_key"), "212");
  assertEquals(url.searchParams.get("rank"), "SPECIES");
  assertEquals(url.searchParams.get("status"), "ACCEPTED");
});

Deno.test("GBIF taxonomy import - retries bounded transient failures", async () => {
  let attempts = 0;
  const waits: number[] = [];
  const retries: unknown[] = [];
  const fetcher: typeof fetch = () => {
    attempts += 1;
    if (attempts === 1) {
      return Promise.reject(new TypeError("temporary transport failure"));
    }
    if (attempts === 2) {
      return Promise.resolve(
        new Response(null, {
          status: 429,
          headers: { "Retry-After": "60" },
        }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          offset: 8_750,
          limit: 100,
          count: 14_641,
          endOfRecords: false,
          results: [{
            key: 2492321,
            rank: "SPECIES",
            canonicalName: "Setophaga petechia",
            class: "Aves",
            classKey: 212,
          }],
        }),
      ),
    );
  };

  const page = await fetchGbifTaxonomyImportPage(
    GBIF_IMPORT_TARGETS.birds,
    8_750,
    100,
    fetcher,
    {
      maximumAttempts: 3,
      wait: (milliseconds) => {
        waits.push(milliseconds);
        return Promise.resolve();
      },
      onRetry: (retry) => retries.push(retry),
    },
  );

  assertEquals(page.offset, 8_750);
  assertEquals(attempts, 3);
  assertEquals(waits, [500, 2_000]);
  assertEquals(retries, [
    {
      attempt: 1,
      maximumAttempts: 3,
      delayMs: 500,
      reason: "transport_error",
    },
    {
      attempt: 2,
      maximumAttempts: 3,
      delayMs: 2_000,
      reason: "http_429",
    },
  ]);
});

Deno.test("GBIF taxonomy import - does not retry permanent HTTP failures", async () => {
  let attempts = 0;
  const fetcher: typeof fetch = () => {
    attempts += 1;
    return Promise.resolve(new Response(null, { status: 400 }));
  };

  await assertRejects(
    () =>
      fetchGbifTaxonomyImportPage(
        GBIF_IMPORT_TARGETS.birds,
        8_750,
        100,
        fetcher,
        {
          maximumAttempts: 3,
          wait: () => Promise.resolve(),
        },
      ),
    Error,
    "GBIF species search failed with HTTP 400.",
  );
  assertEquals(attempts, 1);
});
