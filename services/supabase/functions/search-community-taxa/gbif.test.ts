import { assertEquals } from "@std/assert";
import {
  fetchGbifCommunityTaxa,
  normalizeGbifSuggestEntry,
  shouldFetchGbifCommunityTaxa,
} from "./gbif.ts";

Deno.test("GBIF community taxa - fetch gate requires thin local results and 3 character query", () => {
  assertEquals(shouldFetchGbifCommunityTaxa("ro", 0, 20), false);
  assertEquals(shouldFetchGbifCommunityTaxa("rosa", 5, 20), false);
  assertEquals(shouldFetchGbifCommunityTaxa("rosa", 4, 20), true);
  assertEquals(shouldFetchGbifCommunityTaxa("rosa", 0, 3), true);
  assertEquals(shouldFetchGbifCommunityTaxa("rosa", 3, 3), false);
});

Deno.test("GBIF community taxa - normalizes suggest entries into cache payloads", () => {
  const taxon = normalizeGbifSuggestEntry({
    key: 3000001,
    acceptedKey: 3000001,
    status: "ACCEPTED",
    rank: "SPECIES",
    canonicalName: "Rosa externa",
    vernacularName: "External Rose",
    kingdom: "Plantae",
    phylum: "Tracheophyta",
    class: "Magnoliopsida",
    order: "Rosales",
    family: "Rosaceae",
    genus: "Rosa",
    species: "Rosa externa",
    kingdomKey: 6,
    phylumKey: 7707728,
    classKey: 220,
    orderKey: 691,
    familyKey: 5015,
    genusKey: 3000000,
  });

  assertEquals(taxon?.gbif_taxon_key, 3000001);
  assertEquals(taxon?.accepted_gbif_taxon_key, 3000001);
  assertEquals(taxon?.taxonomic_status, "accepted");
  assertEquals(taxon?.rank, "species");
  assertEquals(taxon?.scientific_name, "Rosa externa");
  assertEquals(taxon?.common_name, "External Rose");
  assertEquals(taxon?.genus_gbif_taxon_key, 3000000);
});

Deno.test("GBIF community taxa - fetch dedupes and drops unsupported entries", async () => {
  const taxa = await fetchGbifCommunityTaxa(
    "rosa",
    10,
    () =>
      Promise.resolve(
        new Response(
          JSON.stringify([
            {
              key: 1,
              rank: "SPECIES",
              canonicalName: "Rosa externa",
              kingdom: "Plantae",
              genus: "Rosa",
            },
            {
              key: 1,
              rank: "SPECIES",
              canonicalName: "Rosa externa",
              kingdom: "Plantae",
              genus: "Rosa",
            },
            {
              key: 2,
              rank: "STRAIN",
              canonicalName: "Unsupported strain",
            },
            {
              key: 3,
              rank: "GENUS",
              canonicalName: "Rosa",
              kingdom: "Plantae",
            },
          ]),
          { status: 200 },
        ),
      ),
  );

  assertEquals(taxa.map((taxon) => taxon.gbif_taxon_key), [1, 3]);
  assertEquals(taxa[1].rank, "genus");
  assertEquals(taxa[1].genus, "Rosa");
});
