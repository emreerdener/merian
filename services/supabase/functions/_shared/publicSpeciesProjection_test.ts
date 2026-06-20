import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildPublicSpeciesDictionaryPayload,
  classifyPublicSpeciesContentQuality,
  isPublicBiologicalSpeciesRow,
  PUBLIC_SPECIES_SCHEMA_VERSION,
  publicSimilarSpeciesMetadata,
  publicSpeciesProjectionForbiddenKeys,
  publicWebReferenceImageAttributionIssues,
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
      {
        url: "https://media.merian.app/public_uploads/pro/photo.webp",
        source: "merian",
        license: "Used with permission via Merian",
        attribution: "Explorer ABC123",
        sort_order: 0,
      },
    ],
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(images, [
    {
      url: "https://media.merian.app/public_uploads/pro/photo.webp",
      source: "merian",
      license: "Used with permission via Merian",
      attribution: "Explorer ABC123",
    },
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

Deno.test("public species projection - merian hosts and row sources sort first", () => {
  const images = referenceImagesFromRows(
    [
      {
        id: "gbif-row",
        url: "https://static.inaturalist.org/photo.jpg",
        source: "gbif",
        sort_order: 0,
      },
      {
        id: "wiki-row",
        url: "https://upload.wikimedia.org/photo.jpg",
        source: "wikipedia",
        sort_order: 0,
      },
      {
        id: "merian-row",
        url: "https://media.merian.app/public_uploads/pro/photo.webp",
        source: null,
        sort_order: 7,
      },
    ],
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(
    images.map((image) => [image.source, image.url]),
    [
      [
        "merian",
        "https://media.merian.app/public_uploads/pro/photo.webp",
      ],
      ["wikipedia", "https://upload.wikimedia.org/photo.jpg"],
      ["gbif", "https://static.inaturalist.org/photo.jpg"],
    ],
  );
});

Deno.test("public species projection - web attribution audit flags incomplete reference media", () => {
  assertEquals(
    publicWebReferenceImageAttributionIssues([
      {
        url: "https://upload.wikimedia.org/complete.jpg",
        source: "wikipedia",
        license: "CC BY-SA 4.0",
        attribution: "Example Photographer",
      },
      {
        url: "https://static.inaturalist.org/missing-license.jpg",
        source: "gbif",
        attribution: "Observer Name",
      },
      {
        url: "https://static.inaturalist.org/missing-both.jpg",
        source: "gbif",
      },
      {
        url: "https://media.merian.app/reference.jpg",
        source: "merian",
        license: "Used with permission via Merian",
        attribution: "Explorer ABC123",
      },
    ]),
    [
      {
        url: "https://static.inaturalist.org/missing-license.jpg",
        source: "gbif",
        missing: ["license"],
      },
      {
        url: "https://static.inaturalist.org/missing-both.jpg",
        source: "gbif",
        missing: ["license", "attribution"],
      },
    ],
  );
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

Deno.test("public species projection - non-biological encyclopedia rows are not public species", () => {
  const availabilityRow = {
    id: "bad-row",
    scientific_name: "Availability",
    common_names: { en: "Availability" },
    alternative_common_names: [],
    kingdom: null,
    phylum: null,
    class: null,
    order: null,
    family: null,
    genus: null,
    wikipedia_url: "https://en.wikipedia.org/wiki/Availability",
    reference_image_url: null,
    wikipedia_overview:
      "In reliability engineering, the term availability has a meaning unrelated to biological taxonomy.",
    hazard_type: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: null,
    group_tags: [],
  };

  assertEquals(isPublicBiologicalSpeciesRow(availabilityRow), false);
  assertEquals(
    isPublicBiologicalSpeciesRow({
      ...availabilityRow,
      scientific_name: "Danaus plexippus",
      common_names: { en: "Monarch Butterfly" },
      kingdom: "Animalia",
      order: "Lepidoptera",
      wikipedia_url: null,
      wikipedia_overview: null,
    }),
    true,
  );
  assertEquals(
    isPublicBiologicalSpeciesRow({
      ...availabilityRow,
      scientific_name: "Sparse taxon",
      common_names: { en: "Sparse Taxon" },
      gbif_taxon_key: 12345,
    }),
    true,
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
