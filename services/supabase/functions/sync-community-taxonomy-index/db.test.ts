import { assertEquals, assertRejects } from "@std/assert";
import {
  type CommunityTaxonomyIndexSyncRequest,
  parseCommunityTaxonomyIndexSyncRequest,
  runCommunityTaxonomyIndexSync,
} from "./db.ts";
import {
  GBIF_IMPORT_TARGETS,
  type GbifCommunityTaxon,
  type GbifTaxonomyImportPage,
} from "./gbif.ts";

const TEST_TAXON: GbifCommunityTaxon = {
  gbif_taxon_key: 2492321,
  accepted_gbif_taxon_key: 2492321,
  taxonomic_status: "accepted",
  rank: "species",
  scientific_name: "Setophaga petechia",
  common_name: "Yellow Warbler",
  kingdom: "Animalia",
  phylum: "Chordata",
  class: "Aves",
  order: "Passeriformes",
  family: "Parulidae",
  genus: "Setophaga",
  species: "Setophaga petechia",
  kingdom_gbif_taxon_key: 1,
  phylum_gbif_taxon_key: 44,
  class_gbif_taxon_key: 212,
  order_gbif_taxon_key: 729,
  family_gbif_taxon_key: 9608,
  genus_gbif_taxon_key: 2492311,
};

function testRequest(
  overrides: Partial<CommunityTaxonomyIndexSyncRequest> = {},
): CommunityTaxonomyIndexSyncRequest {
  return {
    target: GBIF_IMPORT_TARGETS.birds,
    offset: null,
    limit: 100,
    pageCount: 2,
    dryRun: false,
    refreshCoverage: true,
    retry: false,
    ...overrides,
  };
}

function testPage(offset: number): GbifTaxonomyImportPage {
  return {
    offset,
    limit: 100,
    count: 14_641,
    endOfRecords: false,
    taxa: [{
      ...TEST_TAXON,
      gbif_taxon_key: TEST_TAXON.gbif_taxon_key + offset,
    }],
    rawResultCount: 100,
  };
}

Deno.test("community taxonomy index sync - parses defaults and aliases", () => {
  const defaultResult = parseCommunityTaxonomyIndexSyncRequest({});
  assertEquals(defaultResult.request?.target.slug, "birds");
  assertEquals(defaultResult.request?.offset, null);
  assertEquals(defaultResult.request?.limit, 50);
  assertEquals(defaultResult.request?.pageCount, 1);
  assertEquals(defaultResult.request?.dryRun, false);
  assertEquals(defaultResult.request?.refreshCoverage, true);
  assertEquals(defaultResult.request?.retry, false);

  const customResult = parseCommunityTaxonomyIndexSyncRequest({
    scope: "birds",
    offset: 200,
    page_limit: 100,
    pages: 3,
    dry_run: true,
    refresh_coverage: false,
    retry: true,
  });
  assertEquals(customResult.request?.target.rootGbifTaxonKey, 212);
  assertEquals(customResult.request?.offset, 200);
  assertEquals(customResult.request?.limit, 100);
  assertEquals(customResult.request?.pageCount, 3);
  assertEquals(customResult.request?.dryRun, true);
  assertEquals(customResult.request?.refreshCoverage, false);
  assertEquals(customResult.request?.retry, true);
});

Deno.test("community taxonomy index sync - rejects unsafe inputs", () => {
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ target: "mammals" }), {
    error: "Unsupported taxonomy import target.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ offset: -1 }), {
    error: "offset must be a non-negative integer.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ limit: 201 }), {
    error: "limit must be an integer from 1 to 200.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ page_count: 21 }), {
    error: "page_count must be an integer from 1 to 20.",
    status: 400,
  });
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ dry_run: "yes" }), {
    error: "dry_run must be a boolean.",
    status: 400,
  });
  assertEquals(
    parseCommunityTaxonomyIndexSyncRequest({ refresh_coverage: "no" }),
    {
      error: "refresh_coverage must be a boolean.",
      status: 400,
    },
  );
  assertEquals(parseCommunityTaxonomyIndexSyncRequest({ retry: "yes" }), {
    error: "retry must be a boolean.",
    status: 400,
  });
});

Deno.test("community taxonomy index sync - checkpoints every committed page", async () => {
  const events: string[] = [];
  const supabaseAdmin = {} as Parameters<
    typeof runCommunityTaxonomyIndexSync
  >[1];

  const result = await runCommunityTaxonomyIndexSync(
    testRequest(),
    supabaseAdmin,
    (_target, offset) => {
      events.push(`fetch:${offset}`);
      return Promise.resolve(testPage(offset));
    },
    {
      fetchTargetImportOffset: () => Promise.resolve(8_750),
      upsertGbifImportPage: (_admin, _taxa, _query, _request, page) => {
        events.push(`upsert:${page.offset}`);
        return Promise.resolve(1);
      },
      updateTargetImportCursor: (
        _admin,
        _request,
        _pages,
        nextOffset,
        errorMessage,
      ) => {
        events.push(`cursor:${nextOffset}:${errorMessage ?? "success"}`);
        return Promise.resolve();
      },
      refreshTaxonomyCoverageTargets: () => {
        events.push("refresh");
        return Promise.resolve();
      },
      recordFailedImportRun: () => Promise.resolve(),
    },
  );

  assertEquals(result.start_offset, 8_750);
  assertEquals(result.next_offset, 8_950);
  assertEquals(events, [
    "fetch:8750",
    "upsert:8750",
    "cursor:8850:success",
    "fetch:8850",
    "upsert:8850",
    "cursor:8950:success",
    "refresh",
    "cursor:8950:success",
  ]);
});

Deno.test("community taxonomy index sync - records the first unprocessed offset", async () => {
  const cursorUpdates: Array<{
    pageOffsets: number[];
    nextOffset: number;
    errorMessage: string | null;
  }> = [];
  const failedRuns: Array<{ requestedQuery: string; pageOffset: number }> = [];
  const supabaseAdmin = {} as Parameters<
    typeof runCommunityTaxonomyIndexSync
  >[1];

  await assertRejects(
    () =>
      runCommunityTaxonomyIndexSync(
        testRequest(),
        supabaseAdmin,
        (_target, offset) => {
          if (offset === 8_850) {
            return Promise.reject(new Error("GBIF unavailable"));
          }
          return Promise.resolve(testPage(offset));
        },
        {
          fetchTargetImportOffset: () => Promise.resolve(8_750),
          upsertGbifImportPage: () => Promise.resolve(1),
          updateTargetImportCursor: (
            _admin,
            _request,
            pages,
            nextOffset,
            errorMessage,
          ) => {
            cursorUpdates.push({
              pageOffsets: pages.map((page) => page.offset),
              nextOffset,
              errorMessage,
            });
            return Promise.resolve();
          },
          refreshTaxonomyCoverageTargets: () => Promise.resolve(),
          recordFailedImportRun: (
            _admin,
            requestedQuery,
            _request,
            page,
          ) => {
            failedRuns.push({ requestedQuery, pageOffset: page.offset });
            return Promise.resolve();
          },
        },
      ),
    Error,
    "GBIF unavailable",
  );

  assertEquals(cursorUpdates, [
    {
      pageOffsets: [8_750],
      nextOffset: 8_850,
      errorMessage: null,
    },
    {
      pageOffsets: [8_750],
      nextOffset: 8_850,
      errorMessage: "GBIF unavailable",
    },
  ]);
  assertEquals(failedRuns, [{
    requestedQuery:
      "bounded:birds:root=212:rank=species:status=accepted:offset=8850:limit=100",
    pageOffset: 8_850,
  }]);
});
