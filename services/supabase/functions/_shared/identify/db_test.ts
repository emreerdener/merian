import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { speciesReferenceImageRowsFromCache } from "./db.ts";

Deno.test("speciesReferenceImageRowsFromCache splits, dedupes, and maps sources", () => {
  const rows = speciesReferenceImageRowsFromCache(
    "species-id",
    [
      "https://example.org/wiki-hero.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://upload.wikimedia.org/photo-b.jpg",
    ].join(", "),
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(
    rows.map((row) => ({
      species_id: row.species_id,
      url: row.url,
      source: row.source,
      sort_order: row.sort_order,
    })),
    [
      {
        species_id: "species-id",
        url: "https://example.org/wiki-hero.jpg",
        source: "wikipedia",
        sort_order: 0,
      },
      {
        species_id: "species-id",
        url: "https://static.inaturalist.org/photo-a.jpg",
        source: "gbif",
        sort_order: 1,
      },
      {
        species_id: "species-id",
        url: "https://upload.wikimedia.org/photo-b.jpg",
        source: "wikipedia",
        sort_order: 2,
      },
    ],
  );
});

Deno.test("speciesReferenceImageRowsFromCache returns no rows for sparse cache", () => {
  assertEquals(
    speciesReferenceImageRowsFromCache("species-id", " , ", null),
    [],
  );
});
