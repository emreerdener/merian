import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
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
