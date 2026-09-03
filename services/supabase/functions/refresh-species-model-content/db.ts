import { SupabaseClient } from "@supabase/supabase-js";
import {
  fetchGroupTags,
  fetchSimilarSpecies,
  fetchStaticEncyclopedicData,
} from "../_shared/biology.ts";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { updateGroupTags } from "../_shared/identify/db.ts";
import { hasUsableLookalikeTaxonomy } from "../_shared/taxonomy.ts";
import {
  getCachedSpecies,
  updateSpeciesEnrichment,
} from "../enrich-scan/db.ts";
import {
  type LookalikeTaxonFetcher,
  prepareLookalikeCandidates,
} from "./lookalikeCandidates.ts";

export interface SpeciesModelContentDependencies {
  fetchSimilarSpecies?: typeof fetchSimilarSpecies;
  fetchLookalikeTaxon?: LookalikeTaxonFetcher;
}

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
  dependencies: SpeciesModelContentDependencies = {},
): Promise<SpeciesModelContentRefreshRunResult> {
  const jobs = await claimSpeciesModelJobs(supabaseAdmin, request);

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

  const results = await refreshModelJobsWithConcurrency(
    jobs,
    supabaseAdmin,
    dependencies,
  );
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
  dependencies: SpeciesModelContentDependencies = {},
): Promise<SpeciesModelContentRefreshResult> {
  try {
    const result = await refreshSpeciesModelContentJobUnchecked(
      job,
      supabaseAdmin,
      dependencies,
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
  dependencies: SpeciesModelContentDependencies,
): Promise<SpeciesModelContentRefreshResult> {
  switch (job.content_group) {
    case "habitat":
      return await refreshHabitat(job, supabaseAdmin);
    case "lookalikes":
      return await refreshLookalikes(job, supabaseAdmin, dependencies);
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
    "en",
    "gemini-2.5-flash",
  );
  recordAIUsageBestEffort(supabaseAdmin, {
    operation: "scan_overview_enrichment",
    model: "gemini-2.5-flash",
    usage: enrichment.usage,
    inputModality: "text",
  });
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
  dependencies: SpeciesModelContentDependencies,
): Promise<SpeciesModelContentRefreshResult> {
  const cachedSpecies = await getCachedSpecies(
    job.scientific_name,
    supabaseAdmin,
  );
  if (!cachedSpecies || cachedSpecies.id !== job.species_id) {
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

  const similarResult =
    await (dependencies.fetchSimilarSpecies ?? fetchSimilarSpecies)(
      "system:refresh-species-model-content",
      job.scientific_name,
      {
        kingdom: cachedSpecies.kingdom,
        class: cachedSpecies.class,
        order: cachedSpecies.order,
        family: cachedSpecies.family,
      },
      "gemini-2.5-flash",
    );

  if (similarResult?.usage) {
    recordAIUsageBestEffort(supabaseAdmin, {
      operation: "scan_lookalike_enrichment",
      model: "gemini-2.5-flash",
      usage: similarResult.usage,
      inputModality: "text",
    });
  }

  if (!similarResult || !Array.isArray(similarResult.similar_species)) {
    return baseResult(
      job,
      "failed",
      false,
      "Lookalike generation did not return a candidate list.",
    );
  }
  const prepared = await prepareLookalikeCandidates(
    job.scientific_name,
    cachedSpecies,
    similarResult.similar_species,
    dependencies.fetchLookalikeTaxon,
  );
  let persistedCount = 0;
  let unresolvedCount = prepared.unresolvedCount;
  if (prepared.candidates.length > 0 || unresolvedCount === 0) {
    const { data, error } = await supabaseAdmin.rpc(
      "persist_species_model_lookalikes",
      {
        target_species_id: job.species_id,
        candidates: prepared.candidates,
        resolution_complete: unresolvedCount === 0,
      },
    );
    if (error) {
      throw new Error("Failed to persist validated lookalike candidates.");
    }
    const counts = Array.isArray(data) && data.length === 1 ? data[0] : null;
    if (
      !counts ||
      ![counts.persisted_count, counts.unresolved_count, counts.rejected_count]
        .every((value) =>
          Number.isSafeInteger(value) && value >= 0 && value <= 3
        ) ||
      counts.persisted_count + counts.unresolved_count +
            counts.rejected_count !==
        prepared.candidates.length
    ) {
      throw new Error("Lookalike persistence returned an invalid outcome.");
    }
    persistedCount = counts.persisted_count;
    unresolvedCount += counts.unresolved_count;
  }
  if (unresolvedCount > 0) {
    return baseResult(
      job,
      "failed",
      persistedCount > 0,
      "Lookalike candidates remain unresolved.",
    );
  }
  return baseResult(
    job,
    persistedCount > 0 ? "refreshed" : "no_data",
    persistedCount > 0,
  );
}

async function refreshGroupTags(
  job: SpeciesModelEnrichmentJobRow,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesModelContentRefreshResult> {
  const result = await fetchGroupTags(
    "system:refresh-species-model-content",
    job.scientific_name,
    "gemini-2.5-flash",
    supabaseAdmin,
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
  const { data, error } = await supabaseAdmin.rpc(
    "claim_species_model_enrichment_jobs",
    {
      max_rows: request.limit,
      as_of: request.asOf,
      target_content_groups: request.contentGroups ?? MODEL_CONTENT_GROUPS,
      preview_only: request.dryRun,
    },
  );
  if (error) {
    throw new Error("Failed to read species model enrichment jobs.");
  }
  return (data ?? []) as SpeciesModelEnrichmentJobRow[];
}

async function refreshModelJobsWithConcurrency(
  jobs: SpeciesModelEnrichmentJobRow[],
  supabaseAdmin: SupabaseClient,
  dependencies: SpeciesModelContentDependencies,
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
        dependencies,
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
