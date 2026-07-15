import { SupabaseClient } from "@supabase/supabase-js";

export const DEFAULT_IMPORT_RUN_LIMIT = 10;
export const DEFAULT_JOB_LIMIT = 10;
export const MAX_STATUS_LIMIT = 50;

export interface CommunityTaxonomyStatusRequest {
  importRunLimit: number;
  jobLimit: number;
  view: "full" | "coverage";
  target: "birds" | null;
}

export interface CommunityTaxonomyStatusRequestResult {
  request?: CommunityTaxonomyStatusRequest;
  error?: string;
  status?: number;
}

export interface CountRow {
  key: string;
  count: number;
}

export interface CommunityTaxonomyStatusResponse {
  generated_at: string;
  view: "full" | "coverage";
  active_taxonomy: Record<string, unknown> | null;
  node_counts_by_source: CountRow[];
  node_counts_by_rank: CountRow[];
  latest_import_runs: Record<string, unknown>[];
  enrichment_jobs: {
    counts: Array<{ content_group: string; status: string; count: number }>;
    next_jobs: Record<string, unknown>[];
    recent_failures: Record<string, unknown>[];
  };
  coverage_targets: Record<string, unknown>[];
}

const TAXON_SOURCES = ["merian_dictionary", "gbif", "mixed", "manual"];
const TAXON_RANKS = [
  "kingdom",
  "phylum",
  "class",
  "order",
  "family",
  "genus",
  "species",
  "subspecies",
  "variety",
  "form",
];
const ENRICHMENT_GROUPS = [
  "gbif_wikipedia_reference",
  "habitat",
  "lookalikes",
  "group_tags",
];
const ENRICHMENT_STATUSES = [
  "queued",
  "running",
  "succeeded",
  "failed",
  "cancelled",
];

export function parseCommunityTaxonomyStatusRequest(
  body: Record<string, unknown> = {},
): CommunityTaxonomyStatusRequestResult {
  const importLimit = parseLimit(
    body.import_run_limit ?? body.importRunLimit,
    "import_run_limit",
    DEFAULT_IMPORT_RUN_LIMIT,
  );
  if (importLimit.error) return importLimit;

  const jobLimit = parseLimit(
    body.job_limit ?? body.jobLimit ?? body.failure_limit ?? body.failureLimit,
    "job_limit",
    DEFAULT_JOB_LIMIT,
  );
  if (jobLimit.error) return jobLimit;

  const viewResult = parseView(body.view);
  if (viewResult.error) return viewResult;

  const targetResult = parseTarget(body.target ?? body.scope);
  if (targetResult.error) return targetResult;

  return {
    request: {
      importRunLimit: importLimit.limit ?? DEFAULT_IMPORT_RUN_LIMIT,
      jobLimit: jobLimit.limit ?? DEFAULT_JOB_LIMIT,
      view: viewResult.view ?? "full",
      target: targetResult.target ?? null,
    },
  };
}

export async function fetchCommunityTaxonomyStatus(
  request: CommunityTaxonomyStatusRequest,
  supabaseAdmin: SupabaseClient,
): Promise<CommunityTaxonomyStatusResponse> {
  if (request.view === "coverage") {
    return await fetchCommunityTaxonomyCoverageStatus(request, supabaseAdmin);
  }

  const activeTaxonomy = await fetchActiveTaxonomy(supabaseAdmin);
  const taxonomyVersionId = activeTaxonomy?.id as string | undefined;

  const [
    totalNodeCount,
    speciesNodeCount,
    dictionarySpeciesCount,
    gbifOnlyTaxaCount,
    nodeCountsBySource,
    nodeCountsByRank,
    latestImportRuns,
    enrichmentJobCounts,
    nextJobs,
    recentFailures,
    coverageTargets,
  ] = await Promise.all([
    countTaxonNodes(supabaseAdmin, taxonomyVersionId),
    countTaxonNodes(supabaseAdmin, taxonomyVersionId, { rank: "species" }),
    countTaxonNodes(supabaseAdmin, taxonomyVersionId, {
      dictionaryLinked: true,
    }),
    countTaxonNodes(supabaseAdmin, taxonomyVersionId, {
      gbifOnly: true,
    }),
    countTaxonNodesBySource(supabaseAdmin, taxonomyVersionId),
    countTaxonNodesByRank(supabaseAdmin, taxonomyVersionId),
    fetchLatestImportRuns(supabaseAdmin, request.importRunLimit),
    countSpeciesEnrichmentJobs(supabaseAdmin),
    fetchNextEnrichmentJobs(supabaseAdmin, request.jobLimit),
    fetchRecentEnrichmentFailures(supabaseAdmin, request.jobLimit),
    fetchCoverageTargets(supabaseAdmin),
  ]);

  return {
    generated_at: new Date().toISOString(),
    view: "full",
    active_taxonomy: activeTaxonomy
      ? {
        ...activeTaxonomy,
        node_count: totalNodeCount,
        species_node_count: speciesNodeCount,
        dictionary_species_count: dictionarySpeciesCount,
        gbif_only_taxa_count: gbifOnlyTaxaCount,
      }
      : null,
    node_counts_by_source: nodeCountsBySource,
    node_counts_by_rank: nodeCountsByRank,
    latest_import_runs: latestImportRuns,
    enrichment_jobs: {
      counts: enrichmentJobCounts,
      next_jobs: nextJobs,
      recent_failures: recentFailures,
    },
    coverage_targets: coverageTargets,
  };
}

async function fetchCommunityTaxonomyCoverageStatus(
  request: CommunityTaxonomyStatusRequest,
  supabaseAdmin: SupabaseClient,
): Promise<CommunityTaxonomyStatusResponse> {
  const [latestImportRuns, coverageTargets] = await Promise.all([
    fetchLatestImportRuns(
      supabaseAdmin,
      request.importRunLimit,
      targetImportScope(request.target),
    ),
    fetchCoverageTargets(supabaseAdmin, request.target),
  ]);

  return {
    generated_at: new Date().toISOString(),
    view: "coverage",
    active_taxonomy: null,
    node_counts_by_source: [],
    node_counts_by_rank: [],
    latest_import_runs: latestImportRuns,
    enrichment_jobs: {
      counts: [],
      next_jobs: [],
      recent_failures: [],
    },
    coverage_targets: coverageTargets,
  };
}

async function fetchActiveTaxonomy(
  supabaseAdmin: SupabaseClient,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabaseAdmin
    .from("taxonomy_versions")
    .select("id,status,source,source_revision,activated_at,created_at")
    .eq("status", "active")
    .order("activated_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`taxonomy_versions status query failed: ${error.message}`);
  }
  return data as Record<string, unknown> | null;
}

async function countTaxonNodes(
  supabaseAdmin: SupabaseClient,
  taxonomyVersionId?: string,
  filters: {
    rank?: string;
    source?: string;
    dictionaryLinked?: boolean;
    gbifOnly?: boolean;
  } = {},
): Promise<number> {
  let query = supabaseAdmin
    .from("taxon_nodes")
    .select("id", { count: "exact", head: true });

  if (taxonomyVersionId) {
    query = query.eq("taxonomy_version_id", taxonomyVersionId);
  }
  if (filters.rank) query = query.eq("rank", filters.rank);
  if (filters.source) query = query.eq("source", filters.source);
  if (filters.dictionaryLinked) query = query.not("species_id", "is", null);
  if (filters.gbifOnly) {
    query = query.not("gbif_taxon_key", "is", null).is("species_id", null);
  }

  const { count, error } = await query;
  if (error) {
    throw new Error(`taxon_nodes count query failed: ${error.message}`);
  }
  return count ?? 0;
}

async function countTaxonNodesBySource(
  supabaseAdmin: SupabaseClient,
  taxonomyVersionId?: string,
): Promise<CountRow[]> {
  const counts = await Promise.all(
    TAXON_SOURCES.map(async (source) => ({
      key: source,
      count: await countTaxonNodes(supabaseAdmin, taxonomyVersionId, {
        source,
      }),
    })),
  );
  return counts.filter((row) => row.count > 0);
}

async function countTaxonNodesByRank(
  supabaseAdmin: SupabaseClient,
  taxonomyVersionId?: string,
): Promise<CountRow[]> {
  const counts = await Promise.all(
    TAXON_RANKS.map(async (rank) => ({
      key: rank,
      count: await countTaxonNodes(supabaseAdmin, taxonomyVersionId, { rank }),
    })),
  );
  return counts.filter((row) => row.count > 0);
}

async function fetchLatestImportRuns(
  supabaseAdmin: SupabaseClient,
  limit: number,
  scope?: string | null,
): Promise<Record<string, unknown>[]> {
  let query = supabaseAdmin
    .from("taxonomy_import_runs")
    .select(
      "id,source,scope,status,requested_query,target_taxonomy_version_id,imported_count,updated_count,error_count,error_message,metadata,started_at,finished_at,created_at,updated_at",
    )
    .order("started_at", { ascending: false });

  if (scope) query = query.eq("scope", scope);

  const { data, error } = await query.limit(limit);

  if (error) {
    throw new Error(
      `taxonomy_import_runs status query failed: ${error.message}`,
    );
  }
  return (data ?? []) as Record<string, unknown>[];
}

async function countSpeciesEnrichmentJobs(
  supabaseAdmin: SupabaseClient,
): Promise<Array<{ content_group: string; status: string; count: number }>> {
  const rows = await Promise.all(
    ENRICHMENT_GROUPS.flatMap((contentGroup) =>
      ENRICHMENT_STATUSES.map(async (status) => ({
        content_group: contentGroup,
        status,
        count: await countSpeciesEnrichmentJobsFor(
          supabaseAdmin,
          contentGroup,
          status,
        ),
      }))
    ),
  );
  return rows.filter((row) => row.count > 0);
}

async function countSpeciesEnrichmentJobsFor(
  supabaseAdmin: SupabaseClient,
  contentGroup: string,
  status: string,
): Promise<number> {
  const { count, error } = await supabaseAdmin
    .from("species_enrichment_jobs")
    .select("id", { count: "exact", head: true })
    .eq("content_group", contentGroup)
    .eq("status", status);

  if (error) {
    throw new Error(
      `species_enrichment_jobs count query failed: ${error.message}`,
    );
  }
  return count ?? 0;
}

async function fetchNextEnrichmentJobs(
  supabaseAdmin: SupabaseClient,
  limit: number,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await supabaseAdmin
    .from("species_enrichment_jobs")
    .select(
      "id,species_id,content_group,status,priority,attempts,max_attempts,source_trigger,next_run_at,last_error,created_at,updated_at,species:species_dictionary(scientific_name,common_names)",
    )
    .in("status", ["queued", "failed"])
    .order("priority", { ascending: true })
    .order("next_run_at", { ascending: true })
    .limit(limit);

  if (error) {
    throw new Error(
      `species_enrichment_jobs next query failed: ${error.message}`,
    );
  }
  return (data ?? []).map(normalizeEnrichmentJobRow);
}

async function fetchRecentEnrichmentFailures(
  supabaseAdmin: SupabaseClient,
  limit: number,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await supabaseAdmin
    .from("species_enrichment_jobs")
    .select(
      "id,species_id,content_group,status,priority,attempts,max_attempts,source_trigger,next_run_at,last_error,created_at,updated_at,species:species_dictionary(scientific_name,common_names)",
    )
    .eq("status", "failed")
    .order("updated_at", { ascending: false })
    .limit(limit);

  if (error) {
    throw new Error(
      `species_enrichment_jobs failures query failed: ${error.message}`,
    );
  }
  return (data ?? []).map(normalizeEnrichmentJobRow);
}

export function normalizeEnrichmentJobRow(
  row: Record<string, unknown>,
): Record<string, unknown> {
  const species = row.species as
    | {
      scientific_name?: string;
      common_names?: Record<string, unknown> | null;
    }
    | undefined;
  const { species: _species, ...rest } = row;
  return {
    ...rest,
    scientific_name: species?.scientific_name ?? null,
    common_name: normalizePrimaryCommonName(species?.common_names),
  };
}

function normalizePrimaryCommonName(
  commonNames: Record<string, unknown> | null | undefined,
): string | null {
  const english = commonNames?.en;
  return typeof english === "string" && english.trim().length > 0
    ? english.trim()
    : null;
}

async function fetchCoverageTargets(
  supabaseAdmin: SupabaseClient,
  target?: "birds" | null,
): Promise<Record<string, unknown>[]> {
  let query = supabaseAdmin
    .from("taxonomy_coverage_targets")
    .select(
      "id,slug,display_name,root_rank,root_scientific_name,indexed_species_count,dictionary_species_count,coverage_ratio,last_imported_offset,next_import_offset,last_successful_import_at,last_import_error,gbif_total_count,import_cursor_metadata,last_computed_at,updated_at",
    )
    .order("display_name", { ascending: true });

  if (target) query = query.eq("slug", target);

  const { data, error } = await query;

  if (error) {
    throw new Error(
      `taxonomy_coverage_targets status query failed: ${error.message}`,
    );
  }
  return (data ?? []) as Record<string, unknown>[];
}

function targetImportScope(target: "birds" | null): string | null {
  return target ? `gbif_bounded_${target}` : null;
}

function parseLimit(
  value: unknown,
  fieldName: string,
  defaultValue: number,
): CommunityTaxonomyStatusRequestResult & { limit?: number } {
  if (value === undefined || value === null) return { limit: defaultValue };
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_STATUS_LIMIT
  ) {
    return {
      error: `${fieldName} must be an integer from 1 to ${MAX_STATUS_LIMIT}.`,
      status: 400,
    };
  }
  return { limit: value };
}

function parseView(
  value: unknown,
): CommunityTaxonomyStatusRequestResult & { view?: "full" | "coverage" } {
  if (value === undefined || value === null) return { view: "full" };
  if (typeof value !== "string") {
    return { error: "view must be a string.", status: 400 };
  }
  const normalized = value.trim().toLowerCase();
  if (normalized !== "full" && normalized !== "coverage") {
    return { error: "view must be full or coverage.", status: 400 };
  }
  return { view: normalized };
}

function parseTarget(
  value: unknown,
): CommunityTaxonomyStatusRequestResult & { target?: "birds" | null } {
  if (value === undefined || value === null) return { target: null };
  if (typeof value !== "string") {
    return { error: "target must be a string.", status: 400 };
  }
  const normalized = value.trim().toLowerCase();
  if (normalized !== "birds") {
    return { error: "Unsupported taxonomy status target.", status: 400 };
  }
  return { target: "birds" };
}
