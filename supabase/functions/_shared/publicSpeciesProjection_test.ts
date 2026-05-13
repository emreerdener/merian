import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildPublicSpeciesDictionaryPayload,
  classifyPublicSpeciesContentQuality,
  PUBLIC_SPECIES_SCHEMA_VERSION,
  publicSimilarSpeciesMetadata,
  publicSpeciesProjectionForbiddenKeys,
  referenceImagesFromRows,
  resolveOptionalPublicCommonName,
  resolvePublicCommonName,
} from "./publicSpeciesProjection.ts";

Deno.test("public species projection - schema version is pinned", () => {
  assertEquals(PUBLIC_SPECIES_SCHEMA_VERSION, 1);
});

Deno.test("public species projection - common name fallback is shared", () => {
  assertEquals(
    resolvePublicCommonName(
      { en: "Monarch Butterfly", es: "Mariposa Monarca" },
      "Danaus plexippus",
    ),
    "Monarch Butterfly",
  );
  assertEquals(
    resolvePublicCommonName(
      { fr: "Papillon Monarque", en: "" },
      "Danaus plexippus",
    ),
    "Papillon Monarque",
  );
  assertEquals(
    resolvePublicCommonName({}, "Danaus plexippus"),
    "Danaus plexippus",
  );
  assertEquals(resolveOptionalPublicCommonName({ fr: "Papillon" }), "Papillon");
  assertEquals(resolveOptionalPublicCommonName({}), null);
});

Deno.test("public species projection - reference image rows normalize and preserve metadata", () => {
  const images = referenceImagesFromRows(
    [
      {
        url: "https://example.org/reference.jpg",
        source: "wikipedia",
        license: "CC BY-SA 4.0",
        attribution: "Example Photographer",
        width: 1200,
        height: 800,
      },
      {
        url: "https://example.org/reference.jpg",
        source: "gbif",
      },
      {
        url: "https://static.inaturalist.org/photo.jpg",
        source: null,
      },
    ],
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(images, [
    {
      url: "https://example.org/reference.jpg",
      source: "wikipedia",
      license: "CC BY-SA 4.0",
      attribution: "Example Photographer",
      width: 1200,
      height: 800,
    },
    {
      url: "https://static.inaturalist.org/photo.jpg",
      source: "gbif",
    },
  ]);
});

Deno.test("public species projection - dictionary payload is a whitelist and has no scan fields", () => {
  const payload = buildPublicSpeciesDictionaryPayload(
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
      group_tags: ["animal", "insect"],
      scan_id: "must-not-leak",
      user_id: "must-not-leak",
      field_notes: "must-not-leak",
      ai_reasoning: "must-not-leak",
      gps_lat_exact: 30.2672,
    } as never,
    [
      {
        species_id: "lookalike-id",
        scientific_name: "Limenitis archippus",
        common_name: "Viceroy",
        reference_image_url: null,
        iucn_red_list_status: null,
      },
    ],
  );

  assertEquals(publicSpeciesProjectionForbiddenKeys(payload), []);
  assertEquals(payload.content_quality, "sparse");
  assert(!("scan_id" in payload));
  assert(!("user_id" in payload));
  assert(!("field_notes" in payload));
  assert(!("ai_reasoning" in payload));
  assert(!("gps_lat_exact" in payload));
});

Deno.test("public species projection - content quality is classified from core public sections", () => {
  const baseRow = {
    id: "species-id",
    scientific_name: "Danaus plexippus",
    common_names: { en: "Monarch Butterfly" },
    alternative_common_names: [],
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    wikipedia_url: null,
    reference_image_url: null,
    wikipedia_overview: null,
    hazard_type: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: null,
    group_tags: [],
  };

  assertEquals(
    classifyPublicSpeciesContentQuality(baseRow),
    "needs_enrichment",
  );
  assertEquals(
    classifyPublicSpeciesContentQuality({
      ...baseRow,
      kingdom: "Animalia",
      order: "Lepidoptera",
      reference_image_url: "https://upload.wikimedia.org/monarch.jpg",
    }),
    "sparse",
  );
  assertEquals(
    classifyPublicSpeciesContentQuality({
      ...baseRow,
      kingdom: "Animalia",
      order: "Lepidoptera",
      reference_image_url: "https://upload.wikimedia.org/monarch.jpg",
      wikipedia_overview:
        "The monarch butterfly is a milkweed butterfly in the family Nymphalidae and a familiar migratory species.",
      habitat_description: "Open fields, meadows, and roadsides.",
    }),
    "complete",
  );
});

Deno.test("public species projection - similar species metadata is sanitized", () => {
  assertEquals(
    publicSimilarSpeciesMetadata({
      reason: "  Similar wing pattern.  ",
      visual_traits: [
        "orange wings",
        "orange wings",
        "",
        "black venation",
      ],
      confidence: 1.5,
      source: "model_enrichment",
      review_status: "unreviewed",
      is_bidirectional: true,
      sort_order: 2,
    }),
    {
      reason: "Similar wing pattern.",
      visual_traits: ["orange wings", "black venation"],
      confidence: 1,
      source: "model_enrichment",
      review_status: "unreviewed",
      is_bidirectional: true,
      sort_order: 2,
    },
  );
});

Deno.test("public species projection - contract test catches private-field leaks", () => {
  assertEquals(
    publicSpeciesProjectionForbiddenKeys({
      id: "species-id",
      scan_id: "scan-id",
      similar_species: [
        {
          species_id: "lookalike-id",
          field_notes: "private",
          gps_lat_exact: 30.2672,
        },
      ],
    }),
    [
      "$.scan_id",
      "$.similar_species[0].field_notes",
      "$.similar_species[0].gps_lat_exact",
    ],
  );
});
