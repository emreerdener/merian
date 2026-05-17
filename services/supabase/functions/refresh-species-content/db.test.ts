import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { ExternalEnrichmentData } from "../_shared/external.ts";
import {
  buildSpeciesDictionaryRefreshUpdate,
  buildSpeciesRefreshPlans,
  parseSpeciesContentRefreshRequest,
  referenceImageRowsFromRefreshCache,
  refreshSpeciesContent,
  type SpeciesContentRefreshQueueRow,
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
