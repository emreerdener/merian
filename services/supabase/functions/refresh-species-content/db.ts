import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type ExternalEnrichmentData,
  fetchExternalEnrichment,
} from "../_shared/external.ts";
import {
  legacyReferenceImageUrls,
  type PublicReferenceImageSource,
  referenceImageSource,
  stringValue,
} from "../_shared/publicSpeciesProjection.ts";
import {
  buildSpeciesDictionaryProvenanceRows,
  recordSpeciesContentProvenance,
  type SpeciesContentKey,
  type SpeciesDictionaryProvenanceData,
} from "../_shared/speciesContentProvenance.ts";

export const DEFAULT_REFRESH_LIMIT = 25;
export const MAX_REFRESH_LIMIT = 100;
export const REFRESH_CONCURRENCY = 4;

export const ALL_REFRESH_CONTENT_KEYS: SpeciesContentKey[] = [
  "common_names",
  "alternative_common_names",
  "taxonomy",
  "wikipedia_url",
  "wikipedia_overview",
  "habitat_description",
  "gbif_taxon_key",
  "reference_images",
  "lookalikes",
  "group_tags",
  "iucn_red_list_status",
  "hazard_type",
];

export const SUPPORTED_REFRESH_CONTENT_KEYS: SpeciesContentKey[] = [
  "alternative_common_names",
  "taxonomy",
  "wikipedia_url",
  "wikipedia_overview",
  "gbif_taxon_key",
  "reference_images",
];

const SUPPORTED_KEY_SET = new Set<SpeciesContentKey>(
  SUPPORTED_REFRESH_CONTENT_KEYS,
);
const ALL_KEY_SET = new Set<SpeciesContentKey>(ALL_REFRESH_CONTENT_KEYS);

export interface SpeciesContentRefreshRequest {
  limit: number;
  asOf: string;
  dryRun: boolean;
  contentKeys?: SpeciesContentKey[];
}

export interface SpeciesContentRefreshRequestResult {
  request?: SpeciesContentRefreshRequest;
  error?: string;
  status?: number;
}

export interface SpeciesContentRefreshQueueRow {
  species_id: string;
  scientific_name: string;
  content_key: string;
  source: string | null;
  source_detail: string | null;
  confidence: number | null;
  last_refreshed_at: string | null;
  refresh_after: string | null;
  reason: string | null;
}

export interface SpeciesEnrichmentJobQueueRow {
  job_id: string;
  species_id: string;
  scientific_name: string;
  content_group: string;
  priority: number;
  attempts: number;
  max_attempts: number;
  source_trigger: string;
  metadata: Record<string, unknown>;
}

export interface SpeciesContentRefreshPlan {
  speciesId: string;
  scientificName: string;
  contentKeys: SpeciesContentKey[];
  queueRows: SpeciesContentRefreshQueueRow[];
  jobIds: string[];
}

export type SpeciesContentRefreshSkipReason =
  | "filtered_out"
  | "invalid_content_key"
  | "unsupported_content_key"
  | "missing_species_name";

export interface SpeciesContentRefreshSkippedItem {
  species_id: string | null;
  scientific_name: string | null;
  content_key: string;
  reason: SpeciesContentRefreshSkipReason;
}

export interface SpeciesContentRefreshPlanningResult {
  plans: SpeciesContentRefreshPlan[];
  skipped: SpeciesContentRefreshSkippedItem[];
}

export interface SpeciesDictionaryRefreshUpdate {
  update: Record<string, unknown>;
  provenance: SpeciesDictionaryProvenanceData;
  refreshedKeys: SpeciesContentKey[];
  noDataKeys: SpeciesContentKey[];
}

export interface SpeciesReferenceImageRefreshRow {
  url: string;
  source: PublicReferenceImageSource;
  sort_order: number;
  last_verified_at: string;
}

export type SpeciesContentRefreshStatus =
  | "dry_run"
  | "failed"
  | "no_data"
  | "refreshed";

export interface SpeciesContentRefreshResult {
  species_id: string;
  scientific_name: string;
  requested_keys: SpeciesContentKey[];
  refreshed_keys: SpeciesContentKey[];
  skipped_keys: SpeciesContentKey[];
  status: SpeciesContentRefreshStatus;
  error?: string;
}

export interface SpeciesContentRefreshRunResult {
  queued_count: number;
  planned_count: number;
  refreshed_count: number;
  no_data_count: number;
  failed_count: number;
  skipped_count: number;
  skipped: SpeciesContentRefreshSkippedItem[];
  results: SpeciesContentRefreshResult[];
}

export type ExternalEnrichmentFetcher = (
  scientificName: string,
) => Promise<ExternalEnrichmentData>;

export function parseSpeciesContentRefreshRequest(
  body: Record<string, unknown> = {},
): SpeciesContentRefreshRequestResult {
  const limitResult = parseLimit(body.limit ?? body.max_rows);
  if (limitResult.error) return limitResult;

  const asOfResult = parseAsOf(body.as_of ?? body.asOf);
  if (asOfResult.error) return asOfResult;

  const dryRunResult = parseDryRun(body.dry_run ?? body.dryRun);
  if (dryRunResult.error) return dryRunResult;

  const contentKeysResult = parseContentKeys(body.content_keys);
  if (contentKeysResult.error) return contentKeysResult;

  return {
    request: {
      limit: limitResult.limit ?? DEFAULT_REFRESH_LIMIT,
      asOf: asOfResult.asOf ?? new Date().toISOString(),
      dryRun: dryRunResult.dryRun ?? false,
      contentKeys: contentKeysResult.contentKeys,
    },
  };
}

export async function fetchSpeciesContentRefreshQueue(
  supabaseAdmin: SupabaseClient,
  request: Pick<SpeciesContentRefreshRequest, "limit" | "asOf">,
): Promise<SpeciesContentRefreshQueueRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_species_content_refresh_queue",
    {
      max_rows: request.limit,
      as_of: request.asOf,
    },
  );
  if (error) {
    throw new Error(
      `get_species_content_refresh_queue failed: ${error.message}`,
    );
  }

  return (data ?? []) as SpeciesContentRefreshQueueRow[];
}

export async function fetchSpeciesEnrichmentJobQueue(
  supabaseAdmin: SupabaseClient,
  request: Pick<SpeciesContentRefreshRequest, "limit" | "asOf">,
): Promise<SpeciesEnrichmentJobQueueRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_species_enrichment_jobs",
    {
      max_rows: request.limit,
      as_of: request.asOf,
      target_content_group: "gbif_wikipedia_reference",
    },
  );
  if (error) {
    throw new Error(
      `claim_species_enrichment_jobs failed: ${error.message}`,
    );
  }

  return (data ?? []) as SpeciesEnrichmentJobQueueRow[];
}

export function buildSpeciesRefreshPlans(
  rows: SpeciesContentRefreshQueueRow[],
  requestedContentKeys?: SpeciesContentKey[],
): SpeciesContentRefreshPlanningResult {
  const requestedSet = requestedContentKeys
    ? new Set<SpeciesContentKey>(requestedContentKeys)
    : null;
  const planBySpeciesId = new Map<string, SpeciesContentRefreshPlan>();
  const skipped: SpeciesContentRefreshSkippedItem[] = [];

  for (const row of rows) {
    const contentKey = row.content_key.trim();
    if (!isSpeciesContentKey(contentKey)) {
      skipped.push(skippedItem(row, "invalid_content_key"));
      continue;
    }

    if (requestedSet && !requestedSet.has(contentKey)) {
      skipped.push(skippedItem(row, "filtered_out"));
      continue;
    }

    if (!SUPPORTED_KEY_SET.has(contentKey)) {
      skipped.push(skippedItem(row, "unsupported_content_key"));
      continue;
    }

    const scientificName = stringValue(row.scientific_name);
    if (!scientificName) {
      skipped.push(skippedItem(row, "missing_species_name"));
      continue;
    }

    const speciesId = row.species_id;
    const plan = planBySpeciesId.get(speciesId) ?? {
      speciesId,
      scientificName,
      contentKeys: [],
      queueRows: [],
      jobIds: [],
    };

    if (!plan.contentKeys.includes(contentKey)) {
      plan.contentKeys.push(contentKey);
    }
    plan.queueRows.push(row);
    planBySpeciesId.set(speciesId, plan);
  }

  const sortOrder = new Map(
    SUPPORTED_REFRESH_CONTENT_KEYS.map((key, index) => [key, index]),
  );
  const plans = Array.from(planBySpeciesId.values()).map((plan) => ({
    ...plan,
    contentKeys: plan.contentKeys.sort((lhs, rhs) =>
      (sortOrder.get(lhs) ?? 0) - (sortOrder.get(rhs) ?? 0)
    ),
  }));

  return { plans, skipped };
}

export function buildSpeciesRefreshPlansFromJobs(
  rows: SpeciesEnrichmentJobQueueRow[],
  requestedContentKeys?: SpeciesContentKey[],
): SpeciesContentRefreshPlanningResult {
  const requestedSet = requestedContentKeys
    ? new Set<SpeciesContentKey>(requestedContentKeys)
    : null;
  const defaultJobKeys: SpeciesContentKey[] = [
    "alternative_common_names",
    "taxonomy",
    "wikipedia_url",
    "wikipedia_overview",
    "gbif_taxon_key",
    "reference_images",
  ];
  const planBySpeciesId = new Map<string, SpeciesContentRefreshPlan>();
  const skipped: SpeciesContentRefreshSkippedItem[] = [];

  for (const row of rows) {
    const scientificName = stringValue(row.scientific_name);
    if (!scientificName) {
      skipped.push({
        species_id: row.species_id,
        scientific_name: row.scientific_name,
        content_key: row.content_group,
        reason: "missing_species_name",
      });
      continue;
    }

    const contentKeys = defaultJobKeys.filter((key) =>
      requestedSet == null || requestedSet.has(key)
    );
    if (contentKeys.length === 0) {
      skipped.push({
        species_id: row.species_id,
        scientific_name: row.scientific_name,
        content_key: row.content_group,
        reason: "filtered_out",
      });
      continue;
    }

    const plan = planBySpeciesId.get(row.species_id) ?? {
      speciesId: row.species_id,
      scientificName,
      contentKeys: [],
      queueRows: [],
      jobIds: [],
    };

    for (const contentKey of contentKeys) {
      if (!plan.contentKeys.includes(contentKey)) {
        plan.contentKeys.push(contentKey);
      }
    }
    plan.jobIds.push(row.job_id);
    planBySpeciesId.set(row.species_id, plan);
  }

  const sortOrder = new Map(
    SUPPORTED_REFRESH_CONTENT_KEYS.map((key, index) => [key, index]),
  );
  const plans = Array.from(planBySpeciesId.values()).map((plan) => ({
    ...plan,
    contentKeys: plan.contentKeys.sort((lhs, rhs) =>
      (sortOrder.get(lhs) ?? 0) - (sortOrder.get(rhs) ?? 0)
    ),
  }));

  return { plans, skipped };
}

export function buildSpeciesDictionaryRefreshUpdate(
  contentKeys: SpeciesContentKey[],
  externalData: ExternalEnrichmentData,
): SpeciesDictionaryRefreshUpdate {
  const update: Record<string, unknown> = {};
  const provenance: SpeciesDictionaryProvenanceData = {};
  const refreshedKeys: SpeciesContentKey[] = [];
  const noDataKeys: SpeciesContentKey[] = [];
  const keySet = new Set(contentKeys);

  if (keySet.has("alternative_common_names")) {
    const names = dedupeStrings(externalData.alternativeCommonNames);
    if (names.length > 0) {
      update.alternative_common_names = names;
      provenance.alternative_common_names = names;
      refreshedKeys.push("alternative_common_names");
    } else {
      noDataKeys.push("alternative_common_names");
    }
  }

  if (keySet.has("taxonomy")) {
    const taxonomy = externalData.gbifTaxonomy;
    const taxonomyUpdate = {
      kingdom: stringValue(taxonomy?.kingdom),
      phylum: stringValue(taxonomy?.phylum),
      class: stringValue(taxonomy?.class),
      order: stringValue(taxonomy?.order),
      family: stringValue(taxonomy?.family),
      genus: stringValue(taxonomy?.genus),
    };
    const populatedRanks = Object.entries(taxonomyUpdate).filter(([, value]) =>
      value != null
    );
    if (populatedRanks.length > 0) {
      Object.assign(update, Object.fromEntries(populatedRanks));
      Object.assign(provenance, Object.fromEntries(populatedRanks));
      refreshedKeys.push("taxonomy");
    } else {
      noDataKeys.push("taxonomy");
    }
  }

  if (keySet.has("wikipedia_url")) {
    const wikipediaUrl = stringValue(externalData.wikipediaUrl);
    if (wikipediaUrl) {
      update.wikipedia_url = wikipediaUrl;
      provenance.wikipedia_url = wikipediaUrl;
      refreshedKeys.push("wikipedia_url");
    } else {
      noDataKeys.push("wikipedia_url");
    }
  }

  if (keySet.has("wikipedia_overview")) {
    const wikipediaOverview = stringValue(externalData.wikiExtract);
    if (wikipediaOverview) {
      update.wikipedia_overview = wikipediaOverview;
      provenance.wikipedia_overview = wikipediaOverview;
      refreshedKeys.push("wikipedia_overview");
    } else {
      noDataKeys.push("wikipedia_overview");
    }
  }

  if (keySet.has("gbif_taxon_key")) {
    const gbifKey = positiveInteger(externalData.gbifKey);
    if (gbifKey != null) {
      update.gbif_taxon_key = gbifKey;
      provenance.gbif_taxon_key = gbifKey;
      refreshedKeys.push("gbif_taxon_key");
    } else {
      noDataKeys.push("gbif_taxon_key");
    }
  }

  if (keySet.has("reference_images")) {
    const imageUrlCache = dedupeStrings(
      legacyReferenceImageUrls(externalData.referenceImageUrl),
    ).join(",");
    if (imageUrlCache) {
      update.reference_image_url = imageUrlCache;
      provenance.reference_image_url = imageUrlCache;
      refreshedKeys.push("reference_images");
    } else {
      noDataKeys.push("reference_images");
    }
  }

  return { update, provenance, refreshedKeys, noDataKeys };
}

export function referenceImageRowsFromRefreshCache(
  referenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
  refreshedAt = new Date(),
): SpeciesReferenceImageRefreshRow[] {
  const rows: SpeciesReferenceImageRefreshRow[] = [];
  const seen = new Set<string>();
  const verifiedAt = refreshedAt.toISOString();

  for (const url of legacyReferenceImageUrls(referenceImageUrl)) {
    if (seen.has(url)) continue;
    seen.add(url);
    rows.push({
      url,
      source: referenceImageSource(url, wikipediaUrl, rows.length),
      sort_order: rows.length,
      last_verified_at: verifiedAt,
    });
  }

  return rows;
}

export async function refreshSpeciesContent(
  plan: SpeciesContentRefreshPlan,
  supabaseAdmin: SupabaseClient,
  fetcher: ExternalEnrichmentFetcher = fetchExternalEnrichment,
): Promise<SpeciesContentRefreshResult> {
  const externalData = await fetcher(plan.scientificName);
  const refreshUpdate = buildSpeciesDictionaryRefreshUpdate(
    plan.contentKeys,
    externalData,
  );

  if (Object.keys(refreshUpdate.update).length === 0) {
    return {
      species_id: plan.speciesId,
      scientific_name: plan.scientificName,
      requested_keys: plan.contentKeys,
      refreshed_keys: [],
      skipped_keys: refreshUpdate.noDataKeys,
      status: "no_data",
    };
  }

  const { error } = await supabaseAdmin
    .from("species_dictionary")
    .update(refreshUpdate.update)
    .eq("id", plan.speciesId);
  if (error) {
    throw new Error(
      `species_dictionary refresh failed for ${plan.speciesId}: ${error.message}`,
    );
  }

  if (refreshUpdate.refreshedKeys.includes("reference_images")) {
    await replaceSpeciesReferenceImages(
      plan.speciesId,
      stringValue(refreshUpdate.update.reference_image_url),
      stringValue(refreshUpdate.update.wikipedia_url) ??
        externalData.wikipediaUrl,
      supabaseAdmin,
    );
  }

  await recordSpeciesContentProvenance(
    supabaseAdmin,
    buildSpeciesDictionaryProvenanceRows(
      plan.speciesId,
      refreshUpdate.provenance,
    ),
    "refreshSpeciesContent",
  );

  return {
    species_id: plan.speciesId,
    scientific_name: plan.scientificName,
    requested_keys: plan.contentKeys,
    refreshed_keys: refreshUpdate.refreshedKeys,
    skipped_keys: refreshUpdate.noDataKeys,
    status: "refreshed",
  };
}

export async function runSpeciesContentRefresh(
  request: SpeciesContentRefreshRequest,
  supabaseAdmin: SupabaseClient,
  fetcher: ExternalEnrichmentFetcher = fetchExternalEnrichment,
): Promise<SpeciesContentRefreshRunResult> {
  if (request.dryRun) {
    const queueRows = await fetchSpeciesContentRefreshQueue(
      supabaseAdmin,
      request,
    );
    const planning = buildSpeciesRefreshPlans(queueRows, request.contentKeys);
    return {
      queued_count: queueRows.length,
      planned_count: planning.plans.length,
      refreshed_count: 0,
      no_data_count: 0,
      failed_count: 0,
      skipped_count: planning.skipped.length,
      skipped: planning.skipped,
      results: planning.plans.map((plan) => ({
        species_id: plan.speciesId,
        scientific_name: plan.scientificName,
        requested_keys: plan.contentKeys,
        refreshed_keys: [],
        skipped_keys: [],
        status: "dry_run",
      })),
    };
  }

  const jobRows = await fetchSpeciesEnrichmentJobQueue(
    supabaseAdmin,
    request,
  );
  const legacyQueueRows = jobRows.length === 0
    ? await fetchSpeciesContentRefreshQueue(supabaseAdmin, request)
    : [];
  const planning = jobRows.length > 0
    ? buildSpeciesRefreshPlansFromJobs(jobRows, request.contentKeys)
    : buildSpeciesRefreshPlans(legacyQueueRows, request.contentKeys);
  const queuedCount = jobRows.length > 0
    ? jobRows.length
    : legacyQueueRows.length;

  const results = await refreshPlansWithConcurrency(
    planning.plans,
    supabaseAdmin,
    fetcher,
  );

  return {
    queued_count: queuedCount,
    planned_count: planning.plans.length,
    refreshed_count: results.filter((result) => result.status === "refreshed")
      .length,
    no_data_count: results.filter((result) => result.status === "no_data")
      .length,
    failed_count: results.filter((result) => result.status === "failed")
      .length,
    skipped_count: planning.skipped.length,
    skipped: planning.skipped,
    results,
  };
}

async function refreshPlansWithConcurrency(
  plans: SpeciesContentRefreshPlan[],
  supabaseAdmin: SupabaseClient,
  fetcher: ExternalEnrichmentFetcher,
): Promise<SpeciesContentRefreshResult[]> {
  const results = new Array<SpeciesContentRefreshResult>(plans.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < plans.length) {
      const index = nextIndex;
      nextIndex += 1;
      const plan = plans[index];

      try {
        results[index] = await refreshSpeciesContent(
          plan,
          supabaseAdmin,
          fetcher,
        );
        await completePlanJobs(plan, results[index], supabaseAdmin);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(JSON.stringify({
          event: "species_content_refresh_species_failed",
          species_id: plan.speciesId,
          scientific_name: plan.scientificName,
          error: message,
        }));
        results[index] = {
          species_id: plan.speciesId,
          scientific_name: plan.scientificName,
          requested_keys: plan.contentKeys,
          refreshed_keys: [],
          skipped_keys: [],
          status: "failed",
          error: message,
        };
        await completePlanJobs(plan, results[index], supabaseAdmin);
      }
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(REFRESH_CONCURRENCY, plans.length) },
      () => worker(),
    ),
  );
  return results;
}

async function completePlanJobs(
  plan: SpeciesContentRefreshPlan,
  result: SpeciesContentRefreshResult,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (plan.jobIds.length === 0) return;
  await Promise.all(
    plan.jobIds.map((jobId) =>
      completeSpeciesEnrichmentJob(
        jobId,
        result.status === "refreshed" || result.status === "no_data",
        result.error ?? null,
        supabaseAdmin,
      )
    ),
  );
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
      event: "species_enrichment_job_completion_failed",
      job_id: jobId,
      error: error.message,
    }));
  }
}

async function replaceSpeciesReferenceImages(
  speciesId: string,
  referenceImageUrl: string | null,
  wikipediaUrl: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const images = referenceImageRowsFromRefreshCache(
    referenceImageUrl,
    wikipediaUrl,
  );
  if (images.length === 0) return;

  const { error } = await supabaseAdmin.rpc(
    "replace_species_reference_images",
    {
      p_species_id: speciesId,
      p_images: images,
    },
  );
  if (error) {
    throw new Error(
      `replace_species_reference_images failed for ${speciesId}: ${error.message}`,
    );
  }
}

function parseLimit(value: unknown): SpeciesContentRefreshRequestResult & {
  limit?: number;
} {
  if (value === undefined || value === null) {
    return { limit: DEFAULT_REFRESH_LIMIT };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_REFRESH_LIMIT
  ) {
    return {
      error: `limit must be an integer from 1 to ${MAX_REFRESH_LIMIT}.`,
      status: 400,
    };
  }
  return { limit: value };
}

function parseAsOf(value: unknown): SpeciesContentRefreshRequestResult & {
  asOf?: string;
} {
  if (value === undefined || value === null) return {};
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    return { error: "as_of must be a valid ISO timestamp.", status: 400 };
  }
  return { asOf: new Date(value).toISOString() };
}

function parseDryRun(value: unknown): SpeciesContentRefreshRequestResult & {
  dryRun?: boolean;
} {
  if (value === undefined || value === null) return { dryRun: false };
  if (typeof value !== "boolean") {
    return { error: "dry_run must be a boolean.", status: 400 };
  }
  return { dryRun: value };
}

function parseContentKeys(
  value: unknown,
): SpeciesContentRefreshRequestResult & { contentKeys?: SpeciesContentKey[] } {
  if (value === undefined || value === null) return {};
  if (!Array.isArray(value)) {
    return { error: "content_keys must be an array.", status: 400 };
  }

  const contentKeys: SpeciesContentKey[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") {
      return { error: "content_keys must contain strings only.", status: 400 };
    }
    const contentKey = entry.trim();
    if (!isSpeciesContentKey(contentKey)) {
      return { error: `Unsupported content key: ${entry}`, status: 400 };
    }
    if (!contentKeys.includes(contentKey)) contentKeys.push(contentKey);
  }

  return { contentKeys: contentKeys.length > 0 ? contentKeys : undefined };
}

function isSpeciesContentKey(value: string): value is SpeciesContentKey {
  return ALL_KEY_SET.has(value as SpeciesContentKey);
}

function skippedItem(
  row: SpeciesContentRefreshQueueRow,
  reason: SpeciesContentRefreshSkipReason,
): SpeciesContentRefreshSkippedItem {
  return {
    species_id: stringValue(row.species_id),
    scientific_name: stringValue(row.scientific_name),
    content_key: row.content_key,
    reason,
  };
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values) {
    const trimmed = value.trim();
    if (!trimmed) continue;

    const key = trimmed.toLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    result.push(trimmed);
  }

  return result;
}

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : null;
}
