import {
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildSpeciesDictionaryPayload,
  parseSpeciesDictionaryRequest,
  referenceImagesFrom,
  resolveCommonName,
  sanitizeAlternativeCommonNames,
} from "./db.ts";

Deno.test("species-dictionary helpers - resolve common name fallback order", () => {
  assertEquals(
    resolveCommonName({ en: "Monarch Butterfly", es: "Mariposa Monarca" }, "Danaus plexippus"),
    "Monarch Butterfly",
  );
  assertEquals(
    resolveCommonName({ fr: "Papillon Monarque", en: "" }, "Danaus plexippus"),
    "Papillon Monarque",
  );
  assertEquals(resolveCommonName({}, "Danaus plexippus"), "Danaus plexippus");
});

Deno.test("species-dictionary helpers - split and dedupe reference images", () => {
  const images = referenceImagesFrom(
    [
      "https://upload.wikimedia.org/monarch.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://static.inaturalist.org/photo-b.jpg",
    ].join(", "),
    "https://en.wikipedia.org/wiki/Danaus_plexippus",
  );

  assertEquals(images, [
    { url: "https://upload.wikimedia.org/monarch.jpg", source: "wikipedia" },
    { url: "https://static.inaturalist.org/photo-a.jpg", source: "gbif" },
    { url: "https://static.inaturalist.org/photo-b.jpg", source: "gbif" },
  ]);
});

Deno.test("species-dictionary helpers - positional Wikipedia source fallback", () => {
  const images = referenceImagesFrom(
    "https://example.org/reference.jpg, https://static.inaturalist.org/photo.jpg",
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(images[0].source, "wikipedia");
  assertEquals(images[1].source, "gbif");
});

Deno.test("species-dictionary helpers - sanitize alternative names", () => {
  assertEquals(
    sanitizeAlternativeCommonNames(
      ["Monarch Butterfly", "Milkweed Butterfly", "milkweed butterfly", " Wanderer "],
      "Monarch Butterfly",
    ),
    ["Milkweed Butterfly", "Wanderer"],
  );
});

Deno.test("species-dictionary helpers - build sparse payload with lookalikes", () => {
  const payload = buildSpeciesDictionaryPayload(
    {
      id: "species-id",
      scientific_name: "Danaus plexippus",
      common_names: { en: "Monarch Butterfly" },
      alternative_common_names: ["Milkweed Butterfly"],
      kingdom: "Animalia",
      phylum: null,
      class: null,
      order: "Lepidoptera",
      family: null,
      genus: "Danaus",
      wikipedia_url: null,
      reference_image_url: "https://upload.wikimedia.org/monarch.jpg",
      wikipedia_overview: null,
      hazard_type: null,
      iucn_red_list_status: "least concern",
      habitat_description: null,
      gbif_taxon_key: 5139790,
      group_tags: ["animal", "insect", "animal"],
    },
    [
      {
        scientific_name: "Danaus gilippus",
        common_name: "Queen Butterfly",
        reference_image_url: null,
        iucn_red_list_status: null,
      },
    ],
  );

  assertEquals(payload.common_name, "Monarch Butterfly");
  assertEquals(payload.alternative_common_names, ["Milkweed Butterfly"]);
  assertEquals(payload.taxonomy.order, "Lepidoptera");
  assertEquals(payload.group_tags, ["animal", "insect"]);
  assertEquals(payload.reference_images.length, 1);
  assertEquals(payload.similar_species[0].scientific_name, "Danaus gilippus");
});

Deno.test("species-dictionary helpers - validates request body", () => {
  assertEquals(parseSpeciesDictionaryRequest({ scientific_name: "  Danaus   plexippus  " }), {
    scientificName: "Danaus plexippus",
  });
  assertEquals(parseSpeciesDictionaryRequest({}), {
    error: "Missing required parameter: scientific_name",
    status: 400,
  });
  assertEquals(parseSpeciesDictionaryRequest({ scientific_name: "" }), {
    error: "Missing required parameter: scientific_name",
    status: 400,
  });
});
