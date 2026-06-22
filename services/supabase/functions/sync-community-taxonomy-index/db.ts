import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  fetchGbifTaxonomyImportPage,
  GBIF_IMPORT_TARGETS,
  type GbifCommunityTaxon,
  type GbifTaxonomyImportPage,
  type GbifTaxonomyImportTarget,
} from "./gbif.ts";

export const DEFAULT_IMPORT_LIMIT = 50;
export const MAX_IMPORT_LIMIT = 200;
export const DEFAULT_PAGE_COUNT = 1;
export const MAX_PAGE_COUNT = 5;

export interface CommunityTaxonomyIndexSyncRequest {
  target: GbifTaxonomyImportTarget;
  offset: number;
  limit: number;
  pageCount: number;
  dryRun: boolean;
}

export interface CommunityTaxonomyIndexSyncRequestResult {
  request?: CommunityTaxonomyIndexSyncRequest;
  error?: string;
  status?: number;
}

export interface CommunityTaxonomyIndexSyncPageResult {
  offset: number;
  limit: number;
  requested_query: string;
  fetched_count: number;
  normalized_count: number;
  imported_count: number;
  dry_run: boolean;
  end_of_records: boolean;
  next_offset: number;
}

export interface CommunityTaxonomyIndexSyncRunResult {
  target: string;
  root_gbif_taxon_key: number;
  dry_run: boolean;
  imported_count: number;
  fetched_count: number;
  normalized_count: number;
  end_of_records: boolean;
  next_offset: number;
  pages: CommunityTaxonomyIndexSyncPageResult[];
}

export type GbifTaxonomyPageFetcher = (
  target: GbifTaxonomyImportTarget,
  offset: number,
  limit: number,
) => Promise<GbifTaxonomyImportPage>;

export function parseCommunityTaxonomyIndexSyncRequest(
  body: Record<string, unknown> = {},
): CommunityTaxonomyIndexSyncRequestResult {
  const targetResult = parseTarget(body.target ?? body.scope);
  if (targetResult.error) return targetResult;

  const offsetResult = parseOffset(body.offset);
  if (offsetResult.error) return offsetResult;

  const limitResult = parseLimit(
    body.limit ?? body.page_limit ?? body.pageLimit,
  );
  if (limitResult.error) return limitResult;

  const pageCountResult = parsePageCount(
    body.page_count ?? body.pageCount ?? body.pages,
  );
  if (pageCountResult.error) return pageCountResult;

  const dryRunResult = parseDryRun(body.dry_run ?? body.dryRun);
  if (dryRunResult.error) return dryRunResult;

  return {
    request: {
      target: targetResult.target ?? GBIF_IMPORT_TARGETS.birds,
      offset: offsetResult.offset ?? 0,
      limit: limitResult.limit ?? DEFAULT_IMPORT_LIMIT,
      pageCount: pageCountResult.pageCount ?? DEFAULT_PAGE_COUNT,
      dryRun: dryRunResult.dryRun ?? false,
    },
  };
}

export async function runCommunityTaxonomyIndexSync(
  request: CommunityTaxonomyIndexSyncRequest,
  supabaseAdmin: SupabaseClient,
  fetchPage: GbifTaxonomyPageFetcher = fetchGbifTaxonomyImportPage,
): Promise<CommunityTaxonomyIndexSyncRunResult> {
  const pages: CommunityTaxonomyIndexSyncPageResult[] = [];
  let currentOffset = request.offset;
  let endOfRecords = false;

  for (let pageIndex = 0; pageIndex < request.pageCount; pageIndex += 1) {
    const page = await fetchPage(request.target, currentOffset, request.limit);
    const requestedQuery = buildImportRequestedQuery(request, currentOffset);
    let importedCount = 0;

    if (!request.dryRun && page.taxa.length > 0) {
      importedCount = await upsertGbifImportPage(
        supabaseAdmin,
        page.taxa,
        requestedQuery,
        request,
        page,
      );
    }

    const nextOffset = currentOffset + page.limit;
    pages.push({
      offset: currentOffset,
      limit: page.limit,
      requested_query: requestedQuery,
      fetched_count: page.rawResultCount,
      normalized_count: page.taxa.length,
      imported_count: importedCount,
      dry_run: request.dryRun,
      end_of_records: page.endOfRecords,
      next_offset: nextOffset,
    });

    currentOffset = nextOffset;
    endOfRecords = page.endOfRecords;
    if (endOfRecords || page.taxa.length === 0) break;
  }

  return {
    target: request.target.slug,
    root_gbif_taxon_key: request.target.rootGbifTaxonKey,
    dry_run: request.dryRun,
    imported_count: pages.reduce((sum, page) => sum + page.imported_count, 0),
    fetched_count: pages.reduce((sum, page) => sum + page.fetched_count, 0),
    normalized_count: pages.reduce(
      (sum, page) => sum + page.normalized_count,
      0,
    ),
    end_of_records: endOfRecords,
    next_offset: currentOffset,
    pages,
  };
}

async function upsertGbifImportPage(
  supabaseAdmin: SupabaseClient,
  taxa: GbifCommunityTaxon[],
  requestedQuery: string,
  request: CommunityTaxonomyIndexSyncRequest,
  page: GbifTaxonomyImportPage,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc(
    "upsert_gbif_community_taxa",
    {
      taxa,
      query_text: requestedQuery,
      max_rows: taxa.length,
    },
  );

  if (error) {
    await recordFailedImportRun(
      supabaseAdmin,
      requestedQuery,
      request,
      page,
      error.message,
    );
    throw new Error(`upsert_gbif_community_taxa failed: ${error.message}`);
  }

  await annotateImportRun(
    supabaseAdmin,
    requestedQuery,
    request,
    page,
  );
  return typeof data === "number" ? data : Number(data ?? 0);
}

async function annotateImportRun(
  supabaseAdmin: SupabaseClient,
  requestedQuery: string,
  request: CommunityTaxonomyIndexSyncRequest,
  page: GbifTaxonomyImportPage,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("taxonomy_import_runs")
    .update({
      scope: importScope(request.target),
      metadata: importMetadata(request, page),
      updated_at: new Date().toISOString(),
    })
    .eq("source", "gbif")
    .eq("requested_query", requestedQuery);

  if (error) {
    throw new Error(`taxonomy_import_runs annotation failed: ${error.message}`);
  }
}

async function recordFailedImportRun(
  supabaseAdmin: SupabaseClient,
  requestedQuery: string,
  request: CommunityTaxonomyIndexSyncRequest,
  page: GbifTaxonomyImportPage,
  errorMessage: string,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("taxonomy_import_runs")
    .insert({
      source: "gbif",
      scope: importScope(request.target),
      status: "failed",
      requested_query: requestedQuery,
      imported_count: 0,
      updated_count: 0,
      error_count: 1,
      error_message: errorMessage,
      metadata: importMetadata(request, page),
      finished_at: new Date().toISOString(),
    });
  if (error) {
    console.error(JSON.stringify({
      event: "gbif_taxonomy_import_failure_record_failed",
      requested_query: requestedQuery,
      error: error.message,
    }));
  }
}

function buildImportRequestedQuery(
  request: CommunityTaxonomyIndexSyncRequest,
  offset: number,
): string {
  return [
    "bounded",
    request.target.slug,
    `root=${request.target.rootGbifTaxonKey}`,
    "rank=species",
    "status=accepted",
    `offset=${offset}`,
    `limit=${request.limit}`,
  ].join(":");
}

function importScope(target: GbifTaxonomyImportTarget): string {
  return `gbif_bounded_${target.slug}`;
}

function importMetadata(
  request: CommunityTaxonomyIndexSyncRequest,
  page: GbifTaxonomyImportPage,
): Record<string, unknown> {
  return {
    target: request.target.slug,
    display_name: request.target.displayName,
    root_rank: request.target.rootRank,
    root_scientific_name: request.target.rootScientificName,
    root_gbif_taxon_key: request.target.rootGbifTaxonKey,
    offset: page.offset,
    limit: page.limit,
    page_count: request.pageCount,
    raw_result_count: page.rawResultCount,
    normalized_count: page.taxa.length,
    gbif_count: page.count,
    end_of_records: page.endOfRecords,
  };
}

function parseTarget(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & {
  target?: GbifTaxonomyImportTarget;
} {
  if (value === undefined || value === null) {
    return { target: GBIF_IMPORT_TARGETS.birds };
  }
  if (typeof value !== "string") {
    return { error: "target must be a string.", status: 400 };
  }
  const normalized = value.trim().toLowerCase();
  if (normalized !== "birds") {
    return { error: "Unsupported taxonomy import target.", status: 400 };
  }
  return { target: GBIF_IMPORT_TARGETS.birds };
}

function parseOffset(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { offset?: number } {
  if (value === undefined || value === null) return { offset: 0 };
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return { error: "offset must be a non-negative integer.", status: 400 };
  }
  return { offset: value };
}

function parseLimit(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { limit?: number } {
  if (value === undefined || value === null) {
    return { limit: DEFAULT_IMPORT_LIMIT };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_IMPORT_LIMIT
  ) {
    return {
      error: `limit must be an integer from 1 to ${MAX_IMPORT_LIMIT}.`,
      status: 400,
    };
  }
  return { limit: value };
}

function parsePageCount(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { pageCount?: number } {
  if (value === undefined || value === null) {
    return { pageCount: DEFAULT_PAGE_COUNT };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_PAGE_COUNT
  ) {
    return {
      error: `page_count must be an integer from 1 to ${MAX_PAGE_COUNT}.`,
      status: 400,
    };
  }
  return { pageCount: value };
}

function parseDryRun(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { dryRun?: boolean } {
  if (value === undefined || value === null) return { dryRun: false };
  if (typeof value !== "boolean") {
    return { error: "dry_run must be a boolean.", status: 400 };
  }
  return { dryRun: value };
}
