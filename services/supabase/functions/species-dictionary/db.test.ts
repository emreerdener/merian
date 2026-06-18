import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildExternalSpeciesDictionaryPayload,
  buildSpeciesDictionaryCatalogItem,
  buildSpeciesDictionaryPayload,
  buildSpeciesDictionaryTree,
  firstReferenceImageUrl,
  parseSpeciesDictionaryRequest,
  publicSpeciesProjectionForbiddenKeys,
  referenceImagesFrom,
  referenceImagesFromRows,
  resolveCommonName,
  sanitizeAlternativeCommonNames,
  speciesReferenceImageLookupBatches,
} from "./db.ts";

Deno.test("species-dictionary helpers - resolve common name fallback order", () => {
  assertEquals(
    resolveCommonName(
      { en: "Monarch Butterfly", es: "Mariposa Monarca" },
      "Danaus plexippus",
    ),
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

Deno.test("species-dictionary helpers - map normalized reference image rows with metadata", () => {
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

Deno.test("species-dictionary helpers - first reference image reads legacy cache", () => {
  assertEquals(
    firstReferenceImageUrl(
      "  , https://upload.wikimedia.org/monarch.jpg, https://example.com/second.jpg",
    ),
    "https://upload.wikimedia.org/monarch.jpg",
  );
  assertEquals(firstReferenceImageUrl(null), null);
});

Deno.test("species-dictionary helpers - batches reference image lookups", () => {
  assertEquals(
    speciesReferenceImageLookupBatches(
      ["a", "b", "a", " ", "c", "d", "e"],
      2,
    ),
    [["a", "b"], ["c", "d"], ["e"]],
  );
  assertEquals(speciesReferenceImageLookupBatches(["a"], 0), [["a"]]);
});

Deno.test("species-dictionary helpers - sanitize alternative names", () => {
  assertEquals(
    sanitizeAlternativeCommonNames(
      [
        "Monarch Butterfly",
        "Milkweed Butterfly",
        "milkweed butterfly",
        " Wanderer ",
      ],
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
        species_id: "lookalike-id",
        scientific_name: "Danaus gilippus",
        common_name: "Queen Butterfly",
        reference_image_url: null,
        iucn_red_list_status: null,
        reason: "Similar orange-and-black wing pattern.",
        visual_traits: ["orange wings", "dark veins"],
        confidence: 0.82,
        source: "model_enrichment",
        review_status: "unreviewed",
        is_bidirectional: false,
        sort_order: 0,
      },
    ],
  );

  assertEquals(payload.common_name, "Monarch Butterfly");
  assertEquals(payload.content_quality, "sparse");
  assertEquals(payload.alternative_common_names, ["Milkweed Butterfly"]);
  assertEquals(payload.taxonomy.order, "Lepidoptera");
  assertEquals(payload.group_tags, ["animal", "insect"]);
  assertEquals(payload.reference_images.length, 1);
  assertEquals(payload.similar_species[0].species_id, "lookalike-id");
  assertEquals(payload.similar_species[0].scientific_name, "Danaus gilippus");
  assertEquals(
    payload.similar_species[0].reason,
    "Similar orange-and-black wing pattern.",
  );
  assertEquals(payload.similar_species[0].visual_traits, [
    "orange wings",
    "dark veins",
  ]);
  assertEquals(payload.similar_species[0].confidence, 0.82);
});

Deno.test("species-dictionary helpers - build external payload for unscanned species", () => {
  const payload = buildExternalSpeciesDictionaryPayload(
    "  Danaus   gilippus ",
    {
      wikipediaUrl: "https://en.wikipedia.org/wiki/Danaus_gilippus",
      wikiExtract:
        "The queen butterfly is a North and South American butterfly in the genus Danaus.",
      gbifKey: 5139791,
      referenceImageUrl:
        "https://upload.wikimedia.org/queen.jpg,https://static.inaturalist.org/queen-observation.jpg",
      alternativeCommonNames: ["Queen Butterfly", "Queen"],
      wikiTitle: "Queen butterfly",
      gbifTaxonomy: {
        kingdom: "Animalia",
        phylum: "Arthropoda",
        class: "Insecta",
        order: "Lepidoptera",
        family: "Nymphalidae",
        genus: "Danaus",
      },
    },
    [
      {
        scientific_name: "Danaus plexippus",
        common_name: "Monarch Butterfly",
        reference_image_url: null,
        iucn_red_list_status: null,
        reason: "Similar orange wing pattern.",
        visual_traits: ["orange wings"],
        confidence: 0.8,
        source: "model_enrichment",
        review_status: "unreviewed",
        is_bidirectional: false,
        sort_order: 0,
      },
    ],
  );

  assertEquals(payload.id, "external:danaus%20gilippus");
  assertEquals(payload.scientific_name, "Danaus gilippus");
  assertEquals(payload.common_name, "Queen butterfly");
  assertEquals(payload.alternative_common_names, ["Queen"]);
  assertEquals(payload.taxonomy.family, "Nymphalidae");
  assertEquals(payload.wikipedia_overview?.includes("queen butterfly"), true);
  assertEquals(payload.gbif_taxon_key, 5139791);
  assertEquals(payload.reference_images.length, 2);
  assertEquals(payload.reference_images[0].source, "wikipedia");
  assertEquals(payload.similar_species[0].species_id, undefined);
  assertEquals(payload.similar_species[0].scientific_name, "Danaus plexippus");
});

Deno.test("species-dictionary helpers - validates request body", () => {
  assertEquals(
    parseSpeciesDictionaryRequest({
      species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    }),
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientific_name: "  Danaus   plexippus  ",
    }),
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      scientific_name: "  Danaus   plexippus  ",
    }),
    {
      scientificName: "Danaus plexippus",
    },
  );
  assertEquals(parseSpeciesDictionaryRequest({ species_id: "not-a-uuid" }), {
    error: "species_id must be a valid UUID.",
    status: 400,
  });
  assertEquals(parseSpeciesDictionaryRequest({}), {
    error: "Missing required parameter: species_id or scientific_name",
    status: 400,
  });
  assertEquals(parseSpeciesDictionaryRequest({ scientific_name: "" }), {
    error: "Missing required parameter: species_id or scientific_name",
    status: 400,
  });
});

Deno.test("species-dictionary helpers - validates catalog request body", () => {
  assertEquals(parseSpeciesDictionaryRequest({ mode: "catalog" }), {
    mode: "catalog",
    limit: 40,
  });
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      query: "  monarch   butterfly ",
      limit: 250,
      cursor: {
        scientific_name: "  Danaus   plexippus ",
        species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      },
    }),
    {
      mode: "catalog",
      query: "monarch butterfly",
      limit: 100,
      cursor: {
        scientificName: "Danaus plexippus",
        speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      },
    },
  );
  assertEquals(parseSpeciesDictionaryRequest({ mode: "tree" }), {
    mode: "tree",
  });
  assertEquals(parseSpeciesDictionaryRequest({ mode: "detail" }), {
    error: "mode must be catalog or tree when provided.",
    status: 400,
  });
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      cursor: {
        scientific_name: "Danaus plexippus",
        species_id: "not-a-uuid",
      },
    }),
    {
      error: "cursor.species_id must be a valid UUID.",
      status: 400,
    },
  );
});

Deno.test("species-dictionary helpers - builds taxonomy tree payload", () => {
  const tree = buildSpeciesDictionaryTree(
    [
      speciesRow({
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        common_names: { en: "Monarch Butterfly" },
        family: "Nymphalidae",
        genus: "Danaus",
      }),
      speciesRow({
        id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
        scientific_name: "Danaus gilippus",
        common_names: { en: "Queen Butterfly" },
        family: "Nymphalidae",
        genus: "Danaus",
      }),
      speciesRow({
        id: "3cf79982-e5ee-4e3d-8d65-274527e6ae03",
        scientific_name: "Mysteria incognita",
        common_names: {},
        kingdom: null,
        phylum: null,
        class: null,
        order: null,
        family: null,
        genus: null,
      }),
    ],
    new Map([
      [
        "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        "https://example.com/monarch.jpg",
      ],
    ]),
  );

  const danausNode = tree.nodes.find((node) =>
    node.id ===
      "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
  );
  const monarchNode = tree.nodes.find((node) =>
    node.id === "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"
  );
  const unclassifiedKingdom = tree.nodes.find((node) =>
    node.id === "taxonomy:kingdom:unclassified"
  );

  assertEquals(danausNode?.species_count, 2);
  assertEquals(danausNode?.child_count, 2);
  assertEquals(
    danausNode?.representative_species?.reference_image_url,
    "https://example.com/monarch.jpg",
  );
  assertEquals(monarchNode?.species?.scientific_name, "Danaus plexippus");
  assertEquals(monarchNode?.parent_id, danausNode?.id);
  assertEquals(unclassifiedKingdom?.title, "Unclassified");
  assertEquals(
    tree.edges.some((edge) =>
      edge.from === danausNode?.id && edge.to === monarchNode?.id
    ),
    true,
  );
});

Deno.test("species-dictionary helpers - taxonomy tree omits forbidden public fields", () => {
  const tree = buildSpeciesDictionaryTree([
    speciesRow({
      id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientific_name: "Danaus plexippus",
      common_names: { en: "Monarch Butterfly" },
    }),
  ]);

  assertEquals(publicSpeciesProjectionForbiddenKeys(tree), []);
});

Deno.test("species-dictionary helpers - builds catalog item payload", () => {
  const item = buildSpeciesDictionaryCatalogItem(
    {
      id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientific_name: "Danaus plexippus",
      common_names: { en: "Monarch Butterfly" },
      alternative_common_names: ["Milkweed Butterfly"],
      kingdom: "Animalia",
      phylum: "Arthropoda",
      class: "Insecta",
      order: "Lepidoptera",
      family: "Nymphalidae",
      genus: "Danaus",
      wikipedia_url: "https://en.wikipedia.org/wiki/Danaus_plexippus",
      reference_image_url: "https://example.com/legacy.jpg",
      wikipedia_overview:
        "The monarch butterfly is a milkweed butterfly in the family Nymphalidae.",
      hazard_type: "none",
      iucn_red_list_status: "least concern",
      habitat_description: "Open meadows and milkweed patches.",
      gbif_taxon_key: 5139790,
      group_tags: ["animal", "insect", "animal"],
    },
    "https://example.com/reference.jpg",
  );

  assertEquals(item.id, "1cf79982-e5ee-4e3d-8d65-274527e6ae01");
  assertEquals(item.common_name, "Monarch Butterfly");
  assertEquals(item.content_quality, "complete");
  assertEquals(item.taxonomy?.family, "Nymphalidae");
  assertEquals(item.group_tags, ["animal", "insect"]);
  assertEquals(item.reference_image_url, "https://example.com/reference.jpg");
});

function speciesRow(
  overrides: Partial<{
    id: string;
    scientific_name: string;
    common_names: Record<string, unknown>;
    alternative_common_names: string[];
    kingdom: string | null;
    phylum: string | null;
    class: string | null;
    order: string | null;
    family: string | null;
    genus: string | null;
    wikipedia_url: string | null;
    reference_image_url: string | null;
    wikipedia_overview: string | null;
    hazard_type: string | null;
    iucn_red_list_status: string | null;
    habitat_description: string | null;
    gbif_taxon_key: number | null;
    group_tags: string[];
  }>,
) {
  return {
    id: overrides.id ?? "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    scientific_name: overrides.scientific_name ?? "Danaus plexippus",
    common_names: overrides.common_names ?? { en: "Monarch Butterfly" },
    alternative_common_names: overrides.alternative_common_names ?? [],
    kingdom: overrides.kingdom === undefined ? "Animalia" : overrides.kingdom,
    phylum: overrides.phylum === undefined ? "Arthropoda" : overrides.phylum,
    class: overrides.class === undefined ? "Insecta" : overrides.class,
    order: overrides.order === undefined ? "Lepidoptera" : overrides.order,
    family: overrides.family === undefined ? "Nymphalidae" : overrides.family,
    genus: overrides.genus === undefined ? "Danaus" : overrides.genus,
    wikipedia_url: overrides.wikipedia_url ?? null,
    reference_image_url: overrides.reference_image_url ?? null,
    wikipedia_overview: overrides.wikipedia_overview ?? null,
    hazard_type: overrides.hazard_type ?? null,
    iucn_red_list_status: overrides.iucn_red_list_status ?? null,
    habitat_description: overrides.habitat_description ?? null,
    gbif_taxon_key: overrides.gbif_taxon_key ?? null,
    group_tags: overrides.group_tags ?? [],
  };
}
