import { SupabaseClient } from "@supabase/supabase-js";
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
export const MAX_PAGE_COUNT = 20;

export interface CommunityTaxonomyIndexSyncRequest {
  target: GbifTaxonomyImportTarget;
  offset: number | null;
  limit: number;
  pageCount: number;
  dryRun: boolean;
  refreshCoverage: boolean;
  retry: boolean;
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
  retry: boolean;
  refresh_coverage: boolean;
  start_offset: number;
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

  const refreshCoverageResult = parseRefreshCoverage(
    body.refresh_coverage ?? body.refreshCoverage,
  );
  if (refreshCoverageResult.error) return refreshCoverageResult;

  const retryResult = parseRetry(body.retry);
  if (retryResult.error) return retryResult;

  return {
    request: {
      target: targetResult.target ?? GBIF_IMPORT_TARGETS.birds,
      offset: offsetResult.offset ?? null,
      limit: limitResult.limit ?? DEFAULT_IMPORT_LIMIT,
      pageCount: pageCountResult.pageCount ?? DEFAULT_PAGE_COUNT,
      dryRun: dryRunResult.dryRun ?? false,
      refreshCoverage: refreshCoverageResult.refreshCoverage ?? true,
      retry: retryResult.retry ?? false,
    },
  };
}

export async function runCommunityTaxonomyIndexSync(
  request: CommunityTaxonomyIndexSyncRequest,
  supabaseAdmin: SupabaseClient,
  fetchPage: GbifTaxonomyPageFetcher = fetchGbifTaxonomyImportPage,
): Promise<CommunityTaxonomyIndexSyncRunResult> {
  const pages: CommunityTaxonomyIndexSyncPageResult[] = [];
  const startOffset = request.offset ??
    await fetchTargetImportOffset(supabaseAdmin, request);
  let currentOffset = startOffset;
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

  const importedCount = pages.reduce(
    (sum, page) => sum + page.imported_count,
    0,
  );
  if (!request.dryRun && importedCount > 0) {
    if (request.refreshCoverage) {
      await refreshTaxonomyCoverageTargets(supabaseAdmin);
    }
    await updateTargetImportCursor(
      supabaseAdmin,
      request,
      pages,
      currentOffset,
      null,
    );
  }

  return {
    target: request.target.slug,
    root_gbif_taxon_key: request.target.rootGbifTaxonKey,
    dry_run: request.dryRun,
    retry: request.retry,
    refresh_coverage: request.refreshCoverage,
    start_offset: startOffset,
    imported_count: importedCount,
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
      refresh_coverage: false,
    },
  );

  if (error) {
    await updateTargetImportCursor(
      supabaseAdmin,
      request,
      [],
      request.offset ?? page.offset,
      error.message,
    );
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

async function fetchTargetImportOffset(
  supabaseAdmin: SupabaseClient,
  request: CommunityTaxonomyIndexSyncRequest,
): Promise<number> {
  const { data, error } = await supabaseAdmin
    .from("taxonomy_coverage_targets")
    .select("last_imported_offset,next_import_offset,import_cursor_metadata")
    .eq("slug", request.target.slug)
    .maybeSingle();

  if (error) {
    throw new Error(`taxonomy import cursor query failed: ${error.message}`);
  }
  const metadata = data?.import_cursor_metadata as
    | Record<string, unknown>
    | null
    | undefined;
  const failedOffset = normalizeCursorOffset(metadata?.last_failed_offset);
  const lastImportedOffset = normalizeCursorOffset(data?.last_imported_offset);
  const nextImportOffset = normalizeCursorOffset(data?.next_import_offset);

  if (request.retry) {
    return failedOffset ?? lastImportedOffset ?? nextImportOffset ?? 0;
  }

  return nextImportOffset ?? 0;
}

async function refreshTaxonomyCoverageTargets(
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "refresh_taxonomy_coverage_targets",
  );
  if (error) {
    throw new Error(
      `refresh_taxonomy_coverage_targets failed: ${error.message}`,
    );
  }
}

async function updateTargetImportCursor(
  supabaseAdmin: SupabaseClient,
  request: CommunityTaxonomyIndexSyncRequest,
  pages: CommunityTaxonomyIndexSyncPageResult[],
  nextOffset: number,
  errorMessage: string | null,
): Promise<void> {
  if (request.dryRun) return;

  const lastPage = pages.at(-1);
  const importCursorMetadata: Record<string, unknown> = {
    target: request.target.slug,
    limit: request.limit,
    page_count: request.pageCount,
    retry: request.retry,
    refresh_coverage: request.refreshCoverage,
    last_offsets: pages.map((page) => page.offset),
    updated_by: "sync-community-taxonomy-index",
  };
  if (errorMessage) importCursorMetadata.last_failed_offset = nextOffset;

  const patch: Record<string, unknown> = {
    last_import_error: errorMessage,
    import_cursor_metadata: importCursorMetadata,
    updated_at: new Date().toISOString(),
  };

  if (!errorMessage) {
    patch.last_imported_offset = lastPage?.offset ?? nextOffset;
    patch.next_import_offset = nextOffset;
    patch.last_successful_import_at = new Date().toISOString();
    delete importCursorMetadata.last_failed_offset;
    if (typeof lastPage?.normalized_count === "number") {
      patch.import_cursor_metadata = {
        ...importCursorMetadata,
        last_normalized_count: lastPage.normalized_count,
        last_imported_count: lastPage.imported_count,
        next_import_offset: nextOffset,
      };
    }
  }

  const gbifCount = await fetchLatestGbifCountFromImportRun(
    supabaseAdmin,
    request,
    lastPage,
  );
  if (gbifCount != null) patch.gbif_total_count = gbifCount;

  const { error } = await supabaseAdmin
    .from("taxonomy_coverage_targets")
    .update(patch)
    .eq("slug", request.target.slug);

  if (error) {
    throw new Error(`taxonomy import cursor update failed: ${error.message}`);
  }
}

async function fetchLatestGbifCountFromImportRun(
  supabaseAdmin: SupabaseClient,
  request: CommunityTaxonomyIndexSyncRequest,
  lastPage: CommunityTaxonomyIndexSyncPageResult | undefined,
): Promise<number | null> {
  if (!lastPage) return null;
  const { data, error } = await supabaseAdmin
    .from("taxonomy_import_runs")
    .select("metadata")
    .eq("source", "gbif")
    .eq("requested_query", lastPage.requested_query)
    .limit(1)
    .maybeSingle();

  if (error) {
    console.warn(JSON.stringify({
      event: "gbif_taxonomy_import_gbif_count_lookup_failed",
      target: request.target.slug,
      error: error.message,
    }));
    return null;
  }

  const metadata = data?.metadata as Record<string, unknown> | undefined;
  const gbifCount = metadata?.gbif_count;
  return typeof gbifCount === "number" && Number.isFinite(gbifCount)
    ? gbifCount
    : null;
}

function normalizeCursorOffset(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return Math.floor(value);
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
): CommunityTaxonomyIndexSyncRequestResult & { offset?: number | null } {
  if (value === undefined || value === null) return { offset: null };
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

function parseRefreshCoverage(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { refreshCoverage?: boolean } {
  if (value === undefined || value === null) return { refreshCoverage: true };
  if (typeof value !== "boolean") {
    return { error: "refresh_coverage must be a boolean.", status: 400 };
  }
  return { refreshCoverage: value };
}

function parseRetry(
  value: unknown,
): CommunityTaxonomyIndexSyncRequestResult & { retry?: boolean } {
  if (value === undefined || value === null) return { retry: false };
  if (typeof value !== "boolean") {
    return { error: "retry must be a boolean.", status: 400 };
  }
  return { retry: value };
}
