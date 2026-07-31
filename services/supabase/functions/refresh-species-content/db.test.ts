import {
  assertEquals,
  assertExists,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import type { ExternalEnrichmentData } from "../_shared/external.ts";
import {
  buildSpeciesDictionaryRefreshUpdate,
  buildSpeciesRefreshPlans,
  buildSpeciesRefreshPlansFromJobs,
  parseSpeciesContentRefreshRequest,
  referenceImageRowsFromRefreshCache,
  refreshSpeciesContent,
  type SpeciesContentRefreshQueueRow,
  type SpeciesEnrichmentJobQueueRow,
} from "./db.ts";

const QUEUE_ROW_BASE: SpeciesContentRefreshQueueRow = {
  species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  scientific_name: "Danaus plexippus",
  content_key: "wikipedia_url",
  source: "wikipedia",
  source_detail: null,
  confidence: 0.95,
  last_refreshed_at: "2026-01-01T00:00:00.000Z",
  refresh_after: "2026-05-13T00:00:00.000Z",
  reason: "stale",
};

const EXTERNAL_DATA: ExternalEnrichmentData = {
  wikipediaUrl: "https://en.wikipedia.org/wiki/Danaus_plexippus",
  wikiExtract: "The monarch butterfly is a milkweed butterfly.",
  gbifKey: 5139790,
  referenceImageUrl:
    "https://upload.wikimedia.org/monarch.jpg,https://static.inaturalist.org/photo-a.jpg,https://static.inaturalist.org/photo-a.jpg",
  alternativeCommonNames: ["Monarch", "Wanderer", "monarch", " "],
  wikiTitle: "Danaus plexippus",
  gbifTaxonomy: {
    kingdom: " Animalia ",
    phylum: "Arthropoda",
    class: "Insecta",
    order: "Lepidoptera",
    family: "Nymphalidae",
    genus: "Danaus",
  },
};

Deno.test("refresh species content - parses request defaults and optional filters", () => {
  const defaultResult = parseSpeciesContentRefreshRequest({});
  assertExists(defaultResult.request);
  assertEquals(defaultResult.request.limit, 25);
  assertEquals(defaultResult.request.dryRun, false);
  assertEquals(defaultResult.request.contentKeys, undefined);

  const customResult = parseSpeciesContentRefreshRequest({
    limit: 3,
    dry_run: true,
    as_of: "2026-05-13T00:00:00Z",
    content_keys: ["wikipedia_url", "wikipedia_url", "lookalikes"],
  });
  assertEquals(customResult.request?.limit, 3);
  assertEquals(customResult.request?.dryRun, true);
  assertEquals(
    customResult.request?.asOf,
    "2026-05-13T00:00:00.000Z",
  );
  assertEquals(customResult.request?.contentKeys, [
    "wikipedia_url",
    "lookalikes",
  ]);

  assertEquals(parseSpeciesContentRefreshRequest({ limit: 101 }), {
    error: "limit must be an integer from 1 to 100.",
    status: 400,
  });
  assertEquals(
    parseSpeciesContentRefreshRequest({ content_keys: ["not_a_key"] }),
    {
      error: "Unsupported content key: not_a_key",
      status: 400,
    },
  );
});

Deno.test("refresh species content - groups supported queue rows and skips unsafe keys", () => {
  const planning = buildSpeciesRefreshPlans([
    QUEUE_ROW_BASE,
    { ...QUEUE_ROW_BASE, content_key: "reference_images" },
    { ...QUEUE_ROW_BASE, content_key: "lookalikes" },
    {
      ...QUEUE_ROW_BASE,
      species_id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
      scientific_name: "Rosa galeria",
      content_key: "taxonomy",
    },
    { ...QUEUE_ROW_BASE, content_key: "mystery_field" },
  ], ["wikipedia_url", "reference_images", "lookalikes"]);

  assertEquals(planning.plans.length, 1);
  assertEquals(planning.plans[0].contentKeys, [
    "wikipedia_url",
    "reference_images",
  ]);
  assertEquals(
    planning.skipped.map((item) => [item.content_key, item.reason]),
    [
      ["lookalikes", "unsupported_content_key"],
      ["taxonomy", "filtered_out"],
      ["mystery_field", "invalid_content_key"],
    ],
  );
});

Deno.test("refresh species content - builds GBIF/Wikipedia/reference plans from enrichment jobs", () => {
  const jobRows: SpeciesEnrichmentJobQueueRow[] = [{
    job_id: "job-1",
    species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    scientific_name: "Danaus plexippus",
    content_group: "gbif_wikipedia_reference",
    priority: 50,
    attempts: 1,
    max_attempts: 5,
    source_trigger: "community_consensus_materialization",
    metadata: {},
  }];

  const planning = buildSpeciesRefreshPlansFromJobs(jobRows);
  assertEquals(planning.skipped, []);
  assertEquals(planning.plans.length, 1);
  assertEquals(planning.plans[0].jobIds, ["job-1"]);
  assertEquals(planning.plans[0].contentKeys, [
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
    "country_occurrences",
  ]);
});

Deno.test("refresh species content - builds selective dictionary update from external data", () => {
  const update = buildSpeciesDictionaryRefreshUpdate([
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
  ], EXTERNAL_DATA);

  assertEquals(update.update, {
    alternative_common_names: ["Monarch", "Wanderer"],
    kingdom: "Animalia",
    phylum: "Arthropoda",
    class: "Insecta",
    order: "Lepidoptera",
    family: "Nymphalidae",
    genus: "Danaus",
    wikipedia_url: "https://en.wikipedia.org/wiki/Danaus_plexippus",
    wikipedia_overview: "The monarch butterfly is a milkweed butterfly.",
    gbif_taxon_key: 5139790,
    reference_image_url:
      "https://upload.wikimedia.org/monarch.jpg,https://static.inaturalist.org/photo-a.jpg",
  });
  assertEquals(update.refreshedKeys, [
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
  ]);
  assertEquals(update.noDataKeys, []);
});

Deno.test("refresh species content - reports no-data keys without overwriting fields", () => {
  const update = buildSpeciesDictionaryRefreshUpdate([
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
  ], {
    wikipediaUrl: null,
    wikiExtract: null,
    gbifKey: null,
    referenceImageUrl: null,
    alternativeCommonNames: [],
    wikiTitle: null,
    gbifTaxonomy: null,
  });

  assertEquals(update.update, {});
  assertEquals(update.refreshedKeys, []);
  assertEquals(update.noDataKeys, [
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
  ]);
});

Deno.test("refresh species content - maps refreshed reference images for RPC sync", () => {
  const rows = referenceImageRowsFromRefreshCache(
    "https://upload.wikimedia.org/monarch.jpg, https://static.inaturalist.org/photo-a.jpg, https://static.inaturalist.org/photo-a.jpg",
    "https://en.wikipedia.org/wiki/Danaus_plexippus",
    new Date("2026-05-13T00:00:00.000Z"),
  );

  assertEquals(rows, [
    {
      url: "https://upload.wikimedia.org/monarch.jpg",
      source: "wikipedia",
      sort_order: 0,
      last_verified_at: "2026-05-13T00:00:00.000Z",
    },
    {
      url: "https://static.inaturalist.org/photo-a.jpg",
      source: "gbif",
      sort_order: 1,
      last_verified_at: "2026-05-13T00:00:00.000Z",
    },
  ]);
});

Deno.test("refresh species content - excludes suppressed media before cache and RPC sync", () => {
  const blockedImage =
    "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg";
  const safeImage =
    "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg";
  const externalData: ExternalEnrichmentData = {
    ...EXTERNAL_DATA,
    referenceImageUrl: `${blockedImage},${safeImage}`,
  };

  const update = buildSpeciesDictionaryRefreshUpdate(
    ["reference_images"],
    externalData,
  );
  assertEquals(update.update.reference_image_url, safeImage);
  assertEquals(
    referenceImageRowsFromRefreshCache(
      externalData.referenceImageUrl,
      null,
      new Date("2026-05-13T00:00:00.000Z"),
    ),
    [{
      url: safeImage,
      source: "gbif",
      sort_order: 0,
      last_verified_at: "2026-05-13T00:00:00.000Z",
    }],
  );
});

Deno.test("refresh species content - persists refreshed fields and provenance", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const supabase = {
    from(table: string) {
      return {
        update(update: Record<string, unknown>) {
          return {
            eq(column: string, value: string) {
              calls.push({ table, operation: "update", update, column, value });
              return Promise.resolve({ error: null });
            },
          };
        },
        upsert(rows: unknown[], options: Record<string, unknown>) {
          calls.push({ table, operation: "upsert", rows, options });
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const result = await refreshSpeciesContent(
    {
      speciesId: QUEUE_ROW_BASE.species_id,
      scientificName: QUEUE_ROW_BASE.scientific_name,
      contentKeys: ["wikipedia_url", "wikipedia_overview"],
      queueRows: [QUEUE_ROW_BASE],
      jobIds: [],
    },
    supabase,
    () => Promise.resolve(EXTERNAL_DATA),
  );

  assertEquals(result.status, "refreshed");
  assertEquals(result.refreshed_keys, [
    "wikipedia_url",
    "wikipedia_overview",
  ]);
  assertEquals(calls[0], {
    table: "species_dictionary",
    operation: "update",
    update: {
      wikipedia_url: "https://en.wikipedia.org/wiki/Danaus_plexippus",
      wikipedia_overview: "The monarch butterfly is a milkweed butterfly.",
    },
    column: "id",
    value: QUEUE_ROW_BASE.species_id,
  });
  assertEquals(calls[1].table, "species_content_provenance");
  assertEquals(calls[1].operation, "upsert");
});

Deno.test("refresh species content - atomically replaces country occurrences and records GBIF provenance", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const supabase = {
    from(table: string) {
      return {
        update(update: Record<string, unknown>) {
          return {
            eq(column: string, value: string) {
              calls.push({ table, operation: "update", update, column, value });
              return Promise.resolve({ error: null });
            },
          };
        },
        upsert(rows: unknown[], options: Record<string, unknown>) {
          calls.push({ table, operation: "upsert", rows, options });
          return Promise.resolve({ error: null });
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ operation: "rpc", name, args });
      return Promise.resolve({ error: null });
    },
  } as unknown as SupabaseClient;

  const result = await refreshSpeciesContent(
    {
      speciesId: QUEUE_ROW_BASE.species_id,
      scientificName: QUEUE_ROW_BASE.scientific_name,
      contentKeys: ["gbif_taxon_key", "country_occurrences"],
      queueRows: [],
      jobIds: ["job-1"],
    },
    supabase,
    () => Promise.resolve(EXTERNAL_DATA),
    () =>
      Promise.resolve([
        { countryCode: "CA", occurrenceCount: 42 },
        { countryCode: "US", occurrenceCount: 128 },
      ]),
  );

  assertEquals(result.status, "refreshed");
  assertEquals(result.refreshed_keys, [
    "gbif_taxon_key",
    "country_occurrences",
  ]);
  const replacementCall = calls.find((call) =>
    call.name === "replace_species_country_occurrences"
  );
  assertExists(replacementCall);
  assertEquals(
    (replacementCall.args as Record<string, unknown>).p_occurrences,
    [
      { country_code: "CA", occurrence_count: 42 },
      { country_code: "US", occurrence_count: 128 },
    ],
  );
  const provenanceCall = calls.find((call) =>
    call.table === "species_content_provenance"
  );
  assertExists(provenanceCall);
  const provenanceRows = provenanceCall.rows as Array<Record<string, unknown>>;
  const countryProvenance = provenanceRows.find((row) =>
    row.content_key === "country_occurrences"
  );
  assertEquals(countryProvenance?.source, "gbif");
  assertEquals(countryProvenance?.metadata, {
    gbif_taxon_key: 5139790,
    country_count: 2,
    occurrence_count: 170,
  });
});

Deno.test("refresh species content - retries a failed country facet instead of erasing coverage", async () => {
  const supabase = {} as SupabaseClient;

  await assertRejects(
    () =>
      refreshSpeciesContent(
        {
          speciesId: QUEUE_ROW_BASE.species_id,
          scientificName: QUEUE_ROW_BASE.scientific_name,
          contentKeys: ["country_occurrences"],
          queueRows: [],
          jobIds: [],
        },
        supabase,
        () => Promise.resolve(EXTERNAL_DATA),
        () => Promise.resolve(null),
      ),
    Error,
    "GBIF country occurrence refresh failed",
  );
});

Deno.test("refresh species content - uses a known dictionary taxon key when GBIF matching is unavailable", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const supabase = {
    from(table: string) {
      if (table === "species_dictionary") {
        const query = {
          select(columns: string) {
            calls.push({ table, operation: "select", columns });
            return query;
          },
          eq(column: string, value: string) {
            calls.push({ table, operation: "eq", column, value });
            return query;
          },
          maybeSingle() {
            return Promise.resolve({
              data: { gbif_taxon_key: 5139790 },
              error: null,
            });
          },
        };
        return query;
      }

      return {
        upsert(rows: unknown[], options: Record<string, unknown>) {
          calls.push({ table, operation: "upsert", rows, options });
          return Promise.resolve({ error: null });
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ operation: "rpc", name, args });
      return Promise.resolve({ error: null });
    },
  } as unknown as SupabaseClient;
  const unavailableMatch: ExternalEnrichmentData = {
    wikipediaUrl: null,
    wikiExtract: null,
    gbifKey: null,
    referenceImageUrl: null,
    alternativeCommonNames: [],
    wikiTitle: null,
    gbifTaxonomy: null,
    gbifMatchStatus: "unavailable",
  };

  const result = await refreshSpeciesContent(
    {
      speciesId: QUEUE_ROW_BASE.species_id,
      scientificName: QUEUE_ROW_BASE.scientific_name,
      contentKeys: ["country_occurrences"],
      queueRows: [],
      jobIds: [],
    },
    supabase,
    () => Promise.resolve(unavailableMatch),
    (gbifKey) => {
      assertEquals(gbifKey, 5139790);
      return Promise.resolve([{ countryCode: "US", occurrenceCount: 128 }]);
    },
  );

  assertEquals(result.status, "refreshed");
  const replacementCall = calls.find((call) =>
    call.name === "replace_species_country_occurrences"
  );
  assertEquals(
    (replacementCall?.args as Record<string, unknown>).p_gbif_taxon_key,
    5139790,
  );
});

Deno.test("refresh species content - retries an unavailable match when no known taxon key exists", async () => {
  const query = {
    select() {
      return query;
    },
    eq() {
      return query;
    },
    maybeSingle() {
      return Promise.resolve({
        data: { gbif_taxon_key: null },
        error: null,
      });
    },
  };
  const supabase = {
    from(table: string) {
      assertEquals(table, "species_dictionary");
      return query;
    },
  } as unknown as SupabaseClient;
  const unavailableMatch: ExternalEnrichmentData = {
    wikipediaUrl: null,
    wikiExtract: null,
    gbifKey: null,
    referenceImageUrl: null,
    alternativeCommonNames: [],
    wikiTitle: null,
    gbifTaxonomy: null,
    gbifMatchStatus: "unavailable",
  };

  await assertRejects(
    () =>
      refreshSpeciesContent(
        {
          speciesId: QUEUE_ROW_BASE.species_id,
          scientificName: QUEUE_ROW_BASE.scientific_name,
          contentKeys: ["country_occurrences"],
          queueRows: [],
          jobIds: [],
        },
        supabase,
        () => Promise.resolve(unavailableMatch),
      ),
    Error,
    "GBIF taxon match unavailable",
  );
});

Deno.test("refresh species content - retries when durable provenance cannot be recorded", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const supabase = {
    from(table: string) {
      return {
        update(update: Record<string, unknown>) {
          return {
            eq(column: string, value: string) {
              calls.push({ table, operation: "update", update, column, value });
              return Promise.resolve({ error: null });
            },
          };
        },
        upsert(rows: unknown[], options: Record<string, unknown>) {
          calls.push({ table, operation: "upsert", rows, options });
          return Promise.resolve({
            error: { message: "database unavailable" },
          });
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ operation: "rpc", name, args });
      return Promise.resolve({ error: null });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      refreshSpeciesContent(
        {
          speciesId: QUEUE_ROW_BASE.species_id,
          scientificName: QUEUE_ROW_BASE.scientific_name,
          contentKeys: ["country_occurrences"],
          queueRows: [],
          jobIds: [],
        },
        supabase,
        () => Promise.resolve(EXTERNAL_DATA),
        () => Promise.resolve([]),
      ),
    Error,
    "Failed to record species content provenance",
  );

  assertExists(
    calls.find((call) => call.name === "replace_species_country_occurrences"),
  );
});
