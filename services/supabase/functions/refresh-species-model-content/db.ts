import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  fetchGroupTags,
  fetchSimilarSpecies,
  fetchStaticEncyclopedicData,
  type SimilarSpeciesEntry,
} from "../_shared/biology.ts";
import { updateGroupTags } from "../_shared/identify/db.ts";
import { hasUsableLookalikeTaxonomy } from "../_shared/taxonomy.ts";
import {
  getCachedSpecies,
  resolveLookalikesToJoinTable,
  updateSpeciesEnrichment,
} from "../enrich-scan/db.ts";

export const DEFAULT_MODEL_REFRESH_LIMIT = 12;
export const MAX_MODEL_REFRESH_LIMIT = 50;
export const MODEL_REFRESH_CONCURRENCY = 2;

export type SpeciesModelContentGroup =
  | "habitat"
  | "lookalikes"
  | "group_tags";

export const MODEL_CONTENT_GROUPS: SpeciesModelContentGroup[] = [
  "habitat",
  "lookalikes",
  "group_tags",
];

export interface SpeciesModelContentRefreshRequest {
  limit: number;
  asOf: string;
  dryRun: boolean;
  contentGroups?: SpeciesModelContentGroup[];
}

export interface SpeciesModelContentRefreshRequestResult {
  request?: SpeciesModelContentRefreshRequest;
  error?: string;
  status?: number;
}

export interface SpeciesModelEnrichmentJobRow {
  job_id: string;
  species_id: string;
  scientific_name: string;
  content_group: SpeciesModelContentGroup;
  priority: number;
  attempts: number;
  max_attempts: number;
  source_trigger: string;
  metadata: Record<string, unknown>;
}

export type SpeciesModelContentRefreshStatus =
  | "dry_run"
  | "failed"
  | "no_data"
  | "refreshed";

export interface SpeciesModelContentRefreshResult {
  job_id: string;
  species_id: string;
  scientific_name: string;
  content_group: SpeciesModelContentGroup;
  status: SpeciesModelContentRefreshStatus;
  refreshed: boolean;
  error?: string;
}

export interface SpeciesModelContentRefreshRunResult {
  queued_count: number;
  refreshed_count: number;
  no_data_count: number;
  failed_count: number;
  dry_run: boolean;
  results: SpeciesModelContentRefreshResult[];
}

export function parseSpeciesModelContentRefreshRequest(
  body: Record<string, unknown> = {},
): SpeciesModelContentRefreshRequestResult {
  const limitResult = parseLimit(body.limit ?? body.max_rows);
  if (limitResult.error) return limitResult;

  const asOfResult = parseAsOf(body.as_of ?? body.asOf);
  if (asOfResult.error) return asOfResult;

  const dryRunResult = parseDryRun(body.dry_run ?? body.dryRun);
  if (dryRunResult.error) return dryRunResult;

  const groupsResult = parseContentGroups(
    body.content_groups ?? body.contentGroups,
  );
  if (groupsResult.error) return groupsResult;

  return {
    request: {
      limit: limitResult.limit ?? DEFAULT_MODEL_REFRESH_LIMIT,
      asOf: asOfResult.asOf ?? new Date().toISOString(),
      dryRun: dryRunResult.dryRun ?? false,
      contentGroups: groupsResult.contentGroups,
    },
  };
}

export async function runSpeciesModelContentRefresh(
  request: SpeciesModelContentRefreshRequest,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshRunResult> {
  const jobs = request.dryRun
    ? await fetchPendingSpeciesModelJobs(supabaseAdmin, request)
    : await claimSpeciesModelJobs(supabaseAdmin, request);

  if (request.dryRun) {
    return {
      queued_count: jobs.length,
      refreshed_count: 0,
      no_data_count: 0,
      failed_count: 0,
      dry_run: true,
      results: jobs.map((job) => ({
        job_id: job.job_id,
        species_id: job.species_id,
        scientific_name: job.scientific_name,
        content_group: job.content_group,
        status: "dry_run",
        refreshed: false,
      })),
    };
  }

  const results = await refreshModelJobsWithConcurrency(jobs, supabaseAdmin);
  return {
    queued_count: jobs.length,
    refreshed_count: results.filter((result) => result.status === "refreshed")
      .length,
    no_data_count: results.filter((result) => result.status === "no_data")
      .length,
    failed_count: results.filter((result) => result.status === "failed")
      .length,
    dry_run: false,
    results,
  };
}

export async function refreshSpeciesModelContentJob(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  try {
    const result = await refreshSpeciesModelContentJobUnchecked(
      job,
      supabaseAdmin,
    );
    await completeSpeciesEnrichmentJob(
      job.job_id,
      result.status === "refreshed" || result.status === "no_data",
      result.error ?? null,
      supabaseAdmin,
    );
    return result;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await completeSpeciesEnrichmentJob(
      job.job_id,
      false,
      message,
      supabaseAdmin,
    );
    return {
      job_id: job.job_id,
      species_id: job.species_id,
      scientific_name: job.scientific_name,
      content_group: job.content_group,
      status: "failed",
      refreshed: false,
      error: message,
    };
  }
}

async function refreshSpeciesModelContentJobUnchecked(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  switch (job.content_group) {
    case "habitat":
      return await refreshHabitat(job, supabaseAdmin);
    case "lookalikes":
      return await refreshLookalikes(job, supabaseAdmin);
    case "group_tags":
      return await refreshGroupTags(job, supabaseAdmin);
  }
}

async function refreshHabitat(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  const enrichment = await fetchStaticEncyclopedicData(
    "system:refresh-species-model-content",
    job.scientific_name,
  );
  await updateSpeciesEnrichment(
    job.scientific_name,
    enrichment,
    null,
    supabaseAdmin,
  );

  return baseResult(job, "refreshed", true);
}

async function refreshLookalikes(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  const cachedSpecies = await getCachedSpecies(
    job.scientific_name,
    supabaseAdmin,
  );
  if (!cachedSpecies) {
    return baseResult(job, "failed", false, "Species row not found.");
  }

  if (
    !hasUsableLookalikeTaxonomy({
      kingdom: cachedSpecies.kingdom,
      order: cachedSpecies.order,
      family: cachedSpecies.family,
    })
  ) {
    return baseResult(job, "failed", false, "Lookalike taxonomy is not ready.");
  }

  const similarResult = await fetchSimilarSpecies(
    "system:refresh-species-model-content",
    job.scientific_name,
    {
      kingdom: cachedSpecies.kingdom,
      class: cachedSpecies.class,
      order: cachedSpecies.order,
      family: cachedSpecies.family,
    },
  );

  if (!similarResult?.similar_species?.length) {
    return baseResult(job, "no_data", false);
  }

  const resolveResult = await resolveLookalikesToJoinTable(
    cachedSpecies.id,
    similarResult.similar_species,
    supabaseAdmin,
    cachedSpecies.kingdom,
    cachedSpecies.order,
    cachedSpecies.family,
  );

  const persistedLookalikes = resolveResult.lookalikes.filter((entry) =>
    entry.species_id
  );
  const validatedSimilarResult = persistedLookalikes.length > 0
    ? {
      similar_species: persistedLookalikes.map((entry) => ({
        scientific_name: entry.scientific_name,
        common_name: entry.common_name,
      })) satisfies SimilarSpeciesEntry[],
    }
    : null;

  await updateSpeciesEnrichment(
    job.scientific_name,
    null,
    validatedSimilarResult,
    supabaseAdmin,
  );

  if (resolveResult.persisted && persistedLookalikes.length > 0) {
    const { error } = await supabaseAdmin
      .from("species_dictionary")
      .update({ lookalikes_flash_attempted: true })
      .eq("id", cachedSpecies.id);
    if (error) throw error;
    return baseResult(job, "refreshed", true);
  }

  return baseResult(job, "no_data", false);
}

async function refreshGroupTags(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  const result = await fetchGroupTags(
    "system:refresh-species-model-content",
    job.scientific_name,
  );
  const groupTags = sanitizeGroupTags(result?.group_tags);
  if (groupTags.length === 0) {
    return baseResult(job, "no_data", false);
  }

  await updateGroupTags(job.scientific_name, groupTags, supabaseAdmin);
  return baseResult(job, "refreshed", true);
}

async function claimSpeciesModelJobs(
  supabaseAdmin: SupabaseClient,
  request: SpeciesModelContentRefreshRequest,
): Promise<SpeciesModelEnrichmentJobRow[]> {
  const jobs: SpeciesModelEnrichmentJobRow[] = [];
  const groups = request.contentGroups ?? MODEL_CONTENT_GROUPS;

  for (const group of groups) {
    const remaining = request.limit - jobs.length;
    if (remaining <= 0) break;

    const { data, error } = await supabaseAdmin.rpc(
      "claim_species_enrichment_jobs",
      {
        max_rows: remaining,
        as_of: request.asOf,
        target_content_group: group,
      },
    );
    if (error) {
      throw new Error(
        `claim_species_enrichment_jobs failed for ${group}: ${error.message}`,
      );
    }

    jobs.push(...((data ?? []) as SpeciesModelEnrichmentJobRow[]));
  }

  return jobs;
}

async function fetchPendingSpeciesModelJobs(
  supabaseAdmin: SupabaseClient,
  request: SpeciesModelContentRefreshRequest,
): Promise<SpeciesModelEnrichmentJobRow[]> {
  const { data, error } = await supabaseAdmin
    .from("species_enrichment_jobs")
    .select(
      "job_id:id,species_id,content_group,priority,attempts,max_attempts,source_trigger,metadata,species:species_dictionary!inner(scientific_name)",
    )
    .in("content_group", request.contentGroups ?? MODEL_CONTENT_GROUPS)
    .in("status", ["queued", "failed"])
    .lte("next_run_at", request.asOf)
    .order("priority", { ascending: true })
    .order("next_run_at", { ascending: true })
    .limit(request.limit);

  if (error) {
    throw new Error(
      `species_enrichment_jobs dry-run query failed: ${error.message}`,
    );
  }

  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    job_id: String(row.job_id),
    species_id: String(row.species_id),
    scientific_name: String(
      (row.species as { scientific_name?: string } | undefined)
        ?.scientific_name ?? "",
    ),
    content_group: row.content_group as SpeciesModelContentGroup,
    priority: Number(row.priority ?? 100),
    attempts: Number(row.attempts ?? 0),
    max_attempts: Number(row.max_attempts ?? 5),
    source_trigger: String(row.source_trigger ?? "unknown"),
    metadata: row.metadata && typeof row.metadata === "object"
      ? row.metadata as Record<string, unknown>
      : {},
  }));
}

async function refreshModelJobsWithConcurrency(
  jobs: SpeciesModelEnrichmentJobRow[],
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult[]> {
  const results = new Array<SpeciesModelContentRefreshResult>(jobs.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < jobs.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await refreshSpeciesModelContentJob(
        jobs[index],
        supabaseAdmin,
      );
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(MODEL_REFRESH_CONCURRENCY, jobs.length) },
      () => worker(),
    ),
  );

  return results;
}

async function completeSpeciesEnrichmentJob(
  jobId: string,
  succeeded: boolean,
  errorMessage: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "complete_species_enrichment_job",
    {
      target_job_id: jobId,
      succeeded,
      error_message: errorMessage,
    },
  );
  if (error) {
    console.error(JSON.stringify({
      event: "species_model_enrichment_job_completion_failed",
      job_id: jobId,
      error: error.message,
    }));
  }
}

function parseLimit(value: unknown): SpeciesModelContentRefreshRequestResult & {
  limit?: number;
} {
  if (value === undefined || value === null) {
    return { limit: DEFAULT_MODEL_REFRESH_LIMIT };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_MODEL_REFRESH_LIMIT
  ) {
    return {
      error: `limit must be an integer from 1 to ${MAX_MODEL_REFRESH_LIMIT}.`,
      status: 400,
    };
  }
  return { limit: value };
}

function parseAsOf(
  value: unknown,
): SpeciesModelContentRefreshRequestResult & { asOf?: string } {
  if (value === undefined || value === null) return {};
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    return { error: "as_of must be a valid ISO timestamp.", status: 400 };
  }
  return { asOf: new Date(value).toISOString() };
}

function parseDryRun(
  value: unknown,
): SpeciesModelContentRefreshRequestResult & { dryRun?: boolean } {
  if (value === undefined || value === null) return { dryRun: false };
  if (typeof value !== "boolean") {
    return { error: "dry_run must be a boolean.", status: 400 };
  }
  return { dryRun: value };
}

function parseContentGroups(
  value: unknown,
): SpeciesModelContentRefreshRequestResult & {
  contentGroups?: SpeciesModelContentGroup[];
} {
  if (value === undefined || value === null) return {};
  if (!Array.isArray(value)) {
    return { error: "content_groups must be an array.", status: 400 };
  }

  const groups: SpeciesModelContentGroup[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") {
      return {
        error: "content_groups must contain strings only.",
        status: 400,
      };
    }
    if (!isSpeciesModelContentGroup(entry)) {
      return { error: `Unsupported content group: ${entry}`, status: 400 };
    }
    if (!groups.includes(entry)) groups.push(entry);
  }

  return { contentGroups: groups.length > 0 ? groups : undefined };
}

function isSpeciesModelContentGroup(
  value: string,
): value is SpeciesModelContentGroup {
  return (MODEL_CONTENT_GROUPS as string[]).includes(value);
}

function sanitizeGroupTags(values: string[] | null | undefined): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values ?? []) {
    const trimmed = value.trim().toLowerCase().replace(/\s+/g, " ");
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    result.push(trimmed);
    if (result.length >= 5) break;
  }
  return result;
}

function baseResult(
  job: SpeciesModelEnrichmentJobRow,
  status: SpeciesModelContentRefreshStatus,
  refreshed: boolean,
  error?: string,
): SpeciesModelContentRefreshResult {
  return {
    job_id: job.job_id,
    species_id: job.species_id,
    scientific_name: job.scientific_name,
    content_group: job.content_group,
    status,
    refreshed,
    error,
  };
}
