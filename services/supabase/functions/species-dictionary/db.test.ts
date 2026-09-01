import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildExternalSpeciesDictionaryPayload,
  buildSpeciesDictionaryCatalogItem,
  buildSpeciesDictionaryOverview,
  buildSpeciesDictionaryPayload,
  fetchAllPublicSpeciesDictionaryRows,
  fetchSpeciesDictionary,
  fetchSpeciesDictionaryCatalog,
  firstReferenceImageUrl,
  firstReferenceImageUrlsBySpeciesId,
  normalizedCountryCode,
  parseSpeciesDictionaryRequest,
  PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE,
  referenceImageRowsWithAuthors,
  referenceImagesFrom,
  referenceImagesFromRows,
  resolveCommonName,
  sanitizeAlternativeCommonNames,
  SPECIES_DICTIONARY_RECENTLY_ADDED_OVERVIEW_LIMIT,
  speciesDictionaryCatalogCursorFilter,
  speciesReferenceImageLookupBatches,
} from "./db.ts";

function regionalCatalogSupabaseMock(hasCountryCoverage: boolean): {
  client: SupabaseClient;
  calls: Array<{ table: string; method: string; args: unknown[] }>;
} {
  const calls: Array<{ table: string; method: string; args: unknown[] }> = [];
  const client = {
    from(table: string) {
      const response = table === "species_country_occurrences"
        ? {
          data: hasCountryCoverage ? [{ species_id: "species-id" }] : [],
          error: null,
        }
        : { data: [], error: null };
      const query = {
        select(...args: unknown[]) {
          calls.push({ table, method: "select", args });
          return query;
        },
        or(...args: unknown[]) {
          calls.push({ table, method: "or", args });
          return query;
        },
        limit(...args: unknown[]) {
          calls.push({ table, method: "limit", args });
          return query;
        },
        eq(...args: unknown[]) {
          calls.push({ table, method: "eq", args });
          return query;
        },
        gte(...args: unknown[]) {
          calls.push({ table, method: "gte", args });
          return query;
        },
        ilike(...args: unknown[]) {
          calls.push({ table, method: "ilike", args });
          return query;
        },
        order(...args: unknown[]) {
          calls.push({ table, method: "order", args });
          return query;
        },
        then(resolve: (value: typeof response) => unknown) {
          return Promise.resolve(resolve(response));
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;

  return { client, calls };
}

function lookupSupabaseMock(rows: ReturnType<typeof speciesRow>[]): {
  client: SupabaseClient;
  dictionaryLookups: Array<{ column: string; value: unknown }>;
} {
  const dictionaryLookups: Array<{ column: string; value: unknown }> = [];
  const client = {
    from(table: string) {
      const filters = new Map<string, unknown>();
      const query = {
        select: () => query,
        eq(column: string, value: unknown) {
          filters.set(column, value);
          if (table === "species_dictionary") {
            dictionaryLookups.push({ column, value });
          }
          return query;
        },
        neq: () => query,
        in: () => query,
        is: () => query,
        limit: () => query,
        order: () => query,
        then(resolve: (value: { data: unknown[]; error: null }) => unknown) {
          const data = table === "species_dictionary"
            ? rows.filter((row) =>
              Array.from(filters).every(([column, value]) =>
                row[column as keyof typeof row] === value
              )
            )
            : [];
          return Promise.resolve(resolve({ data, error: null }));
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;

  return { client, dictionaryLookups };
}

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

Deno.test("species-dictionary helpers - attach current Naturebook contributor usernames", () => {
  const rows = referenceImageRowsWithAuthors(
    [
      {
        id: "reference-id",
        url: "https://media.merian.app/public_uploads/pro/photo.webp",
        source: "merian",
      },
      {
        id: "legacy-unlinked-reference-id",
        url: "https://media.merian.app/public_uploads/pro/legacy.webp",
        source: "merian",
      },
      {
        id: "wikipedia-id",
        url: "https://upload.wikimedia.org/photo.jpg",
        source: "wikipedia",
      },
    ],
    [
      {
        reference_image_id: "reference-id",
        user_id: "66a06afc-a56f-4d19-bfc3-07cf32c1f458",
        author: { public_username: "ayla" },
      },
      {
        reference_image_id: null,
        image_url: "https://media.merian.app/public_uploads/pro/legacy.webp",
        user_id: "66a06afc-a56f-4d19-bfc3-07cf32c1f459",
        author: { public_username: "legacy_author" },
      },
    ],
  );

  assertEquals(rows[0].author_user_id, "66a06afc-a56f-4d19-bfc3-07cf32c1f458");
  assertEquals(rows[0].author_username, "ayla");
  assertEquals(rows[1].author_user_id, "66a06afc-a56f-4d19-bfc3-07cf32c1f459");
  assertEquals(rows[1].author_username, "legacy_author");
  assertEquals(rows[2].author_user_id, undefined);
  assertEquals(rows[2].author_username, undefined);
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

Deno.test("species-dictionary helpers - first reference image prefers explicit Merian source", () => {
  const firstImages = firstReferenceImageUrlsBySpeciesId([
    {
      id: "wikipedia-row",
      species_id: "species-id",
      url: "https://upload.wikimedia.org/reference.jpg",
      source: "wikipedia",
      sort_order: 0,
      created_at: "2026-06-01T12:00:00Z",
    },
    {
      id: "merian-row",
      species_id: "species-id",
      url: "https://cdn.example.com/merian-upload.webp",
      source: "merian",
      sort_order: 9,
      created_at: "2026-06-02T12:00:00Z",
    },
  ]);

  assertEquals(
    firstImages.get("species-id"),
    "https://cdn.example.com/merian-upload.webp",
  );
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
    category: "all",
    limit: 40,
  });
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      category: "recently_added",
      query: "  monarch   butterfly ",
      limit: 250,
      cursor: {
        scientific_name: "  Danaus   plexippus ",
        species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        created_at: "2026-06-01T12:00:00Z",
      },
    }),
    {
      mode: "catalog",
      category: "recently_added",
      query: "monarch butterfly",
      limit: 100,
      cursor: {
        scientificName: "Danaus plexippus",
        speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        createdAt: "2026-06-01T12:00:00Z",
      },
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      category: "region",
      region: " United   States ",
    }),
    {
      mode: "catalog",
      category: "region",
      region: "United States",
      limit: 40,
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      category: "group",
      group: " Birds ",
    }),
    {
      mode: "catalog",
      category: "group",
      group: "birds",
      limit: 40,
    },
  );
  assertEquals(parseSpeciesDictionaryRequest({ mode: "overview" }), {
    mode: "overview",
  });
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "overview",
      user_region: " United   States ",
    }),
    {
      mode: "overview",
      userRegion: "United States",
    },
  );
  assertEquals(parseSpeciesDictionaryRequest({ mode: "tree" }), {
    error: "mode must be catalog or overview when provided.",
    status: 400,
  });
  assertEquals(parseSpeciesDictionaryRequest({ mode: "detail" }), {
    error: "mode must be catalog or overview when provided.",
    status: 400,
  });
  assertEquals(
    parseSpeciesDictionaryRequest({ mode: "catalog", category: "region" }),
    {
      error: "region is required when category is region.",
      status: 400,
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({ mode: "catalog", category: "popular" }),
    {
      error: "category must be all, region, group, or recently_added.",
      status: 400,
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({ mode: "catalog", category: "group" }),
    {
      error: "group is required when category is group.",
      status: 400,
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      category: "group",
      group: "dinosaurs",
    }),
    {
      error: "group is not supported.",
      status: 400,
    },
  );
  assertEquals(
    parseSpeciesDictionaryRequest({
      mode: "catalog",
      category: "recently_added",
      cursor: {
        scientific_name: "Danaus plexippus",
        species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      },
    }),
    {
      error: "cursor.created_at is required when category is recently_added.",
      status: 400,
    },
  );
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

Deno.test("species-dictionary helpers - quotes keyset cursor values for PostgREST", () => {
  const cursor = {
    scientificName: 'Testus, complexus (form "A")\\variant',
    speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    createdAt: "2026-06-01T12:00:00.000Z",
  };
  const ascendingFilter = speciesDictionaryCatalogCursorFilter(cursor, "all");

  assertEquals(
    ascendingFilter,
    'scientific_name.gt."Testus, complexus (form \\"A\\")\\\\variant",and(scientific_name.eq."Testus, complexus (form \\"A\\")\\\\variant",id.gt."1cf79982-e5ee-4e3d-8d65-274527e6ae01")',
  );
  assertEquals(
    speciesDictionaryCatalogCursorFilter(cursor, "region"),
    ascendingFilter,
  );
  assertEquals(
    speciesDictionaryCatalogCursorFilter(cursor, "group"),
    ascendingFilter,
  );
  assertEquals(
    speciesDictionaryCatalogCursorFilter(cursor, "recently_added"),
    'created_at.lt."2026-06-01T12:00:00.000Z",and(created_at.eq."2026-06-01T12:00:00.000Z",id.lt."1cf79982-e5ee-4e3d-8d65-274527e6ae01")',
  );
});

Deno.test("species-dictionary db - dual identity recovers only from a local name match", async () => {
  const canonicalRow = speciesRow({
    id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
    scientific_name: "Testus floridus",
    gbif_taxon_key: 920002,
  });
  const mock = lookupSupabaseMock([canonicalRow]);
  let externalFetchCount = 0;

  const payload = await fetchSpeciesDictionary(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Testus floridus",
    },
    mock.client,
    {
      fetchExternalSpeciesDictionary: () => {
        externalFetchCount += 1;
        return Promise.reject(new Error("external fetch must not run"));
      },
    },
  );

  assertEquals(payload?.id, canonicalRow.id);
  assertEquals(mock.dictionaryLookups, [
    {
      column: "id",
      value: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    },
    { column: "scientific_name", value: "Testus floridus" },
  ]);
  assertEquals(externalFetchCount, 0);
});

Deno.test("species-dictionary db - dual identity miss never reaches external enrichment", async () => {
  const mock = lookupSupabaseMock([]);
  let externalFetchCount = 0;

  const payload = await fetchSpeciesDictionary(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Missing species",
    },
    mock.client,
    {
      fetchExternalSpeciesDictionary: async () => {
        externalFetchCount += 1;
        return buildExternalSpeciesDictionaryPayload("Missing species", {
          wikipediaUrl: null,
          wikiExtract: null,
          gbifKey: null,
          referenceImageUrl: null,
          alternativeCommonNames: [],
          wikiTitle: null,
          gbifTaxonomy: null,
        });
      },
    },
  );

  assertEquals(payload, null);
  assertEquals(externalFetchCount, 0);
});

Deno.test("species-dictionary db - name-only miss retains bounded external fallback", async () => {
  const mock = lookupSupabaseMock([]);
  let externalFetchCount = 0;

  const payload = await fetchSpeciesDictionary(
    { scientificName: "Externalis exemplaris" },
    mock.client,
    {
      fetchExternalSpeciesDictionary: async (scientificName) => {
        externalFetchCount += 1;
        return buildExternalSpeciesDictionaryPayload(scientificName, {
          wikipediaUrl: null,
          wikiExtract: null,
          gbifKey: 920003,
          referenceImageUrl: null,
          alternativeCommonNames: [],
          wikiTitle: null,
          gbifTaxonomy: null,
        });
      },
    },
  );

  assertEquals(payload?.id, "external:externalis%20exemplaris");
  assertEquals(externalFetchCount, 1);
});

Deno.test("species-dictionary db - ineligible local name is not externalized", async () => {
  const mock = lookupSupabaseMock([
    speciesRow({
      scientific_name: "Availability",
      is_public_biological: false,
    }),
  ]);
  let externalFetchCount = 0;

  const payload = await fetchSpeciesDictionary(
    { scientificName: "Availability" },
    mock.client,
    {
      fetchExternalSpeciesDictionary: async () => {
        externalFetchCount += 1;
        throw new Error("external fetch must not run");
      },
    },
  );

  assertEquals(payload, null);
  assertEquals(externalFetchCount, 0);
});

Deno.test("species-dictionary db - fetches every public row across response pages", async () => {
  const allRows = Array.from(
    { length: PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2 + 1 },
    (_, index) =>
      speciesRow({
        id: `00000000-0000-0000-0000-${String(index + 1).padStart(12, "0")}`,
        scientific_name: `Species paginated ${
          String(index + 1).padStart(4, "0")
        }`,
      }),
  );
  const pages = [
    allRows.slice(0, PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE),
    allRows.slice(
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE,
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2,
    ),
    allRows.slice(PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2),
  ];
  const requestedRanges: Array<[number, number]> = [];
  const query = {
    select: () => query,
    eq: () => query,
    order: () => query,
    range: (from: number, to: number) => {
      requestedRanges.push([from, to]);
      return Promise.resolve({ data: pages.shift() ?? [], error: null });
    },
  };
  const supabaseAdmin = {
    from: () => query,
  } as unknown as SupabaseClient;

  const rows = await fetchAllPublicSpeciesDictionaryRows(supabaseAdmin);

  assertEquals(rows.length, PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2 + 1);
  assertEquals(requestedRanges, [
    [0, PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE - 1],
    [
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE,
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2 - 1,
    ],
    [
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 2,
      PUBLIC_SPECIES_DICTIONARY_PAGE_SIZE * 3 - 1,
    ],
  ]);
});

Deno.test("species-dictionary db - catalog filters canonical coverage by exact country code", async () => {
  const mock = regionalCatalogSupabaseMock(true);

  const result = await fetchSpeciesDictionaryCatalog(
    { mode: "catalog", category: "region", region: "US", limit: 40 },
    mock.client,
  );

  assertEquals(result.data, []);
  const dictionarySelect = mock.calls.find((call) =>
    call.table === "species_dictionary" && call.method === "select"
  );
  assertEquals(
    String(dictionarySelect?.args[0]).includes(
      "species_country_occurrences!inner",
    ),
    true,
  );
  assertEquals(
    mock.calls.some((call) =>
      call.table === "species_dictionary" && call.method === "eq" &&
      call.args[0] === "country_occurrences.country_code" &&
      call.args[1] === "US"
    ),
    true,
  );
  assertEquals(
    mock.calls.some((call) =>
      call.table === "species_dictionary" && call.method === "ilike" &&
      call.args[0] === "native_region"
    ),
    false,
  );
  const dictionaryCalls = mock.calls.filter((call) =>
    call.table === "species_dictionary"
  );
  const eligibilityIndex = dictionaryCalls.findIndex((call) =>
    call.method === "eq" && call.args[0] === "is_public_biological" &&
    call.args[1] === true
  );
  const limitIndex = dictionaryCalls.findIndex((call) =>
    call.method === "limit"
  );
  assertEquals(eligibilityIndex >= 0, true);
  assertEquals(eligibilityIndex < limitIndex, true);
});

Deno.test("species-dictionary db - catalog retains a legacy rollout fallback only without country coverage", async () => {
  const mock = regionalCatalogSupabaseMock(false);

  await fetchSpeciesDictionaryCatalog(
    { mode: "catalog", category: "region", region: "US", limit: 40 },
    mock.client,
  );

  const dictionarySelect = mock.calls.find((call) =>
    call.table === "species_dictionary" && call.method === "select"
  );
  assertEquals(
    String(dictionarySelect?.args[0]).includes(
      "species_country_occurrences!inner",
    ),
    false,
  );
  assertEquals(
    mock.calls.some((call) =>
      call.table === "species_dictionary" && call.method === "ilike" &&
      call.args[0] === "native_region" &&
      call.args[1] === "%United States%"
    ),
    true,
  );
});

Deno.test("species-dictionary helpers - builds overview categories and regions", () => {
  const overview = buildSpeciesDictionaryOverview(
    [
      speciesRow({
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        native_region: "United States",
        created_at: "2026-06-01T12:00:00Z",
      }),
      speciesRow({
        id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
        scientific_name: "Danaus gilippus",
        common_names: { en: "Queen Butterfly" },
        native_region: "North America",
        created_at: "2026-06-03T12:00:00Z",
        wikipedia_overview:
          "The queen butterfly is a milkweed butterfly found across warm habitats and often featured in species guides.",
      }),
      speciesRow({
        id: "3cf79982-e5ee-4e3d-8d65-274527e6ae03",
        scientific_name: "Papilio glaucus",
        native_region: "United States",
        created_at: "2026-06-02T12:00:00Z",
      }),
      speciesRow({
        id: "4cf79982-e5ee-4e3d-8d65-274527e6ae04",
        scientific_name: "Testus ignotus",
        common_names: { en: "Newest Test Species" },
        native_region: "Unknown",
        created_at: "2026-06-04T12:00:00Z",
        wikipedia_overview:
          "The newest test species is used to verify recently added dictionary highlights.",
      }),
      speciesRow({
        id: "5cf79982-e5ee-4e3d-8d65-274527e6ae05",
        scientific_name: "Quercus alba",
        common_names: { en: "White Oak" },
        kingdom: "Plantae",
        class: "Magnoliopsida",
        native_region: "North America",
      }),
      speciesRow({
        id: "6cf79982-e5ee-4e3d-8d65-274527e6ae06",
        scientific_name: "Turdus migratorius",
        common_names: { en: "American Robin" },
        class: "Aves",
        native_region: "North America",
      }),
      speciesRow({
        id: "7cf79982-e5ee-4e3d-8d65-274527e6ae07",
        scientific_name: "Amanita muscaria",
        common_names: { en: "Fly Agaric" },
        kingdom: "Fungi",
        class: "Agaricomycetes",
        native_region: "Northern Hemisphere",
      }),
      speciesRow({
        id: "8cf79982-e5ee-4e3d-8d65-274527e6ae08",
        scientific_name: "Availability",
        common_names: { en: "Availability" },
        kingdom: null,
        phylum: null,
        class: null,
        order: null,
        family: null,
        genus: null,
        native_region: "Internet",
        created_at: "2026-06-05T12:00:00Z",
        wikipedia_overview:
          "In reliability engineering, availability describes whether a system is operational rather than a biological species.",
      }),
    ],
    new Map([
      [
        "3cf79982-e5ee-4e3d-8d65-274527e6ae03",
        "https://example.com/tiger-swallowtail.jpg",
      ],
      [
        "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
        "https://example.com/queen.jpg",
      ],
      [
        "4cf79982-e5ee-4e3d-8d65-274527e6ae04",
        "https://example.com/newest-test-species.jpg",
      ],
      [
        "8cf79982-e5ee-4e3d-8d65-274527e6ae08",
        "https://example.com/not-a-species.jpg",
      ],
    ]),
    "US",
  );

  assertEquals(overview.categories.map((category) => category.id), [
    "all",
    "your_region",
    "recently_added",
  ]);
  assertEquals(
    overview.categories.find((category) => category.id === "your_region")
      ?.count,
    2,
  );
  assertEquals(
    overview.categories.find((category) => category.id === "your_region")
      ?.region,
    "United States",
  );
  assertEquals(
    overview.categories.find((category) => category.id === "your_region")
      ?.region_code,
    "US",
  );
  assertEquals(overview.featured_species?.scientific_name, "Testus ignotus");
  assertEquals(overview.featured_species?.common_name, "Newest Test Species");
  assertEquals(
    overview.categories.find((category) => category.id === "all")?.count,
    7,
  );
  assertEquals(
    overview.featured_species?.overview,
    "The newest test species is used to verify recently added dictionary highlights.",
  );
  assertEquals(
    overview.featured_species?.reference_image_url,
    "https://example.com/newest-test-species.jpg",
  );
  assertEquals(overview.groups.map((group) => group.id), [
    "plants",
    "birds",
    "insects",
    "fungi",
  ]);
  assertEquals(
    overview.groups.find((group) => group.id === "plants")?.count,
    1,
  );
  assertEquals(
    overview.groups.find((group) => group.id === "insects")?.count,
    4,
  );
  assertEquals(
    overview.categories.find((category) => category.id === "recently_added")
      ?.reference_image_url,
    "https://example.com/newest-test-species.jpg",
  );
  assertEquals(overview.regions.map((region) => region.title), [
    "North America",
    "United States",
    "Northern Hemisphere",
  ]);
  assertEquals(overview.regions[0].count, 3);
});

Deno.test("species-dictionary helpers - uses exact country occurrence summaries instead of range text", () => {
  const usRepresentativeId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01";
  const overview = buildSpeciesDictionaryOverview(
    [
      speciesRow({
        id: usRepresentativeId,
        scientific_name: "Danaus plexippus",
        native_region: "North America",
      }),
      speciesRow({
        id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
        scientific_name: "Danaus gilippus",
        native_region: "North America",
      }),
    ],
    new Map([[usRepresentativeId, "https://example.com/monarch.jpg"]]),
    "US",
    [
      {
        country_code: "US",
        species_count: 128,
        representative_species_id: usRepresentativeId,
      },
      {
        country_code: "CA",
        species_count: 42,
        representative_species_id: null,
      },
    ],
    {
      country_code: "US",
      species_count: 128,
      representative_species_id: usRepresentativeId,
    },
  );

  const yourRegion = overview.categories.find((category) =>
    category.id === "your_region"
  );
  assertEquals(yourRegion?.count, 128);
  assertEquals(yourRegion?.region, "United States");
  assertEquals(yourRegion?.region_code, "US");
  assertEquals(yourRegion?.subtitle, "Species recorded in United States");
  assertEquals(
    yourRegion?.reference_image_url,
    "https://example.com/monarch.jpg",
  );
  assertEquals(
    overview.regions.map((region) => [region.code, region.title, region.count]),
    [
      ["US", "United States", 128],
      ["CA", "Canada", 42],
    ],
  );
});

Deno.test("species-dictionary helpers - keeps a zero-coverage user country visible", () => {
  const overview = buildSpeciesDictionaryOverview(
    [speciesRow({ native_region: "North America" })],
    new Map(),
    "DE",
  );
  const yourRegion = overview.categories.find((category) =>
    category.id === "your_region"
  );

  assertEquals(yourRegion?.count, 0);
  assertEquals(yourRegion?.region, "Germany");
  assertEquals(yourRegion?.region_code, "DE");
  assertEquals(
    yourRegion?.subtitle,
    "Regional occurrence coverage for Germany is being prepared",
  );
});

Deno.test("species-dictionary helpers - resolves ISO codes and English country titles", () => {
  assertEquals(normalizedCountryCode("us"), "US");
  assertEquals(normalizedCountryCode("United States"), "US");
  assertEquals(normalizedCountryCode("Canada"), "CA");
  assertEquals(normalizedCountryCode("North America"), null);
});

Deno.test("species-dictionary helpers - recently added overview count is capped to newest entries", () => {
  const rows = Array.from({ length: 45 }, (_, index) => {
    const uuidSuffix = String(index + 1).padStart(12, "0");
    return speciesRow({
      id: `00000000-0000-0000-0000-${uuidSuffix}`,
      scientific_name: `Species recentissima ${index + 1}`,
      common_names: { en: `Recent Species ${index + 1}` },
      created_at: new Date(Date.UTC(2026, 4, index + 1, 12)).toISOString(),
    });
  });
  const overview = buildSpeciesDictionaryOverview(rows);

  assertEquals(
    overview.categories.find((category) => category.id === "all")?.count,
    45,
  );
  assertEquals(
    overview.categories.find((category) => category.id === "recently_added")
      ?.count,
    SPECIES_DICTIONARY_RECENTLY_ADDED_OVERVIEW_LIMIT,
  );
});

Deno.test("species-dictionary helpers - featured species can be newest image-only row", () => {
  const newestImageOnlyId = "9cf79982-e5ee-4e3d-8d65-274527e6ae09";
  const overview = buildSpeciesDictionaryOverview(
    [
      speciesRow({
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        common_names: { en: "Monarch Butterfly" },
        created_at: "2026-06-01T12:00:00Z",
        wikipedia_overview:
          "The monarch butterfly is a milkweed butterfly known for long-distance migration.",
      }),
      speciesRow({
        id: newestImageOnlyId,
        scientific_name: "Imago recentissima",
        common_names: { en: "Newest Image Species" },
        created_at: "2026-06-05T12:00:00Z",
        wikipedia_overview: null,
      }),
    ],
    new Map([
      [
        newestImageOnlyId,
        "https://media.merian.app/public_uploads/pro/newest-image.webp",
      ],
    ]),
  );

  assertEquals(
    overview.featured_species?.scientific_name,
    "Imago recentissima",
  );
  assertEquals(overview.featured_species?.overview, null);
  assertEquals(
    overview.featured_species?.reference_image_url,
    "https://media.merian.app/public_uploads/pro/newest-image.webp",
  );
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
    native_region: string | null;
    created_at: string | null;
    is_public_biological: boolean;
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
    native_region: overrides.native_region ?? "North America",
    created_at: overrides.created_at ?? "2026-01-01T00:00:00Z",
    is_public_biological: overrides.is_public_biological,
  };
}
