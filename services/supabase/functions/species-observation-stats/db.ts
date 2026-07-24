import { SupabaseClient } from "@supabase/supabase-js";
import { readResponseArrayBufferWithinBudget } from "../_shared/mediaBudgets.ts";
import {
  authorizeSpeciesObservationStatsRequest,
  claimSpeciesObservationStatsPopulation,
  finalizeSpeciesObservationStatsPopulation,
  SpeciesObservationStatsError,
  type SpeciesObservationStatsPopulationLease,
  type SpeciesObservationStatsSecurityContext,
} from "./security.ts";

export const SPECIES_OBSERVATION_STATS_SCHEMA_VERSION = 2;
const INAT_BASE_URL = "https://api.inaturalist.org/v1";
const SOURCE = "inaturalist";
const SCOPE = "global";
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const STALE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const NEGATIVE_STALE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const DEFAULT_DELAY_MS = 1000;
const DEFAULT_PROVIDER_REQUEST_TIMEOUT_MS = 5_000;
const DATABASE_TIMEOUT_MS = 5_000;
const DEFAULT_FOREGROUND_DEADLINE_MS = 15_000;
const DEFAULT_BACKGROUND_DEADLINE_MS = 45_000;
const MAX_PROVIDER_RESPONSE_BYTES = 1024 * 1024;
const USER_AGENT =
  "Merian/1.0 species-observation-stats (https://naturebook.earth; public-cache)";

export interface SpeciesObservationStatsRequestResult {
  speciesId?: string;
  scientificName?: string;
  error?: string;
  status?: number;
}

export interface SpeciesObservationMonthCount {
  month: number;
  count: number;
}

export interface SpeciesObservationHistoryCount {
  year: number;
  month: number;
  count: number;
}

export interface SpeciesObservationCategorySeries {
  key: string;
  label: string;
  values: SpeciesObservationMonthCount[];
}

export interface SpeciesObservationStatsPayload {
  species_id: string | null;
  scientific_name: string;
  source: {
    provider: "inaturalist";
    scope: "global";
    inaturalist_taxon_id: number | null;
    fetched_at: string;
  };
  status: "fresh" | "stale" | "no_data" | "unavailable" | "partial";
  total_observations: number;
  last_observation_date: string | null;
  fetched_at: string;
  provider_errors: string[];
  seasonality: SpeciesObservationMonthCount[];
  history: SpeciesObservationHistoryCount[];
  life_stage: SpeciesObservationCategorySeries[];
  sex: SpeciesObservationCategorySeries[];
}

interface SpeciesStatsCacheRow {
  payload?: SpeciesObservationStatsPayload | null;
  status?: SpeciesObservationStatsPayload["status"] | null;
  fetched_at?: string | null;
  expires_at?: string | null;
  provider_error?: string | null;
}

export interface SpeciesObservationStatsFetchOptions {
  securityContext: SpeciesObservationStatsSecurityContext;
  fetcher?: typeof fetch;
  now?: Date;
  delayMs?: number;
  providerRequestTimeoutMs?: number;
  foregroundDeadlineMs?: number;
  backgroundDeadlineMs?: number;
  monotonicNowMs?: () => number;
  runBackground?: (task: Promise<void>) => void;
  onBackgroundRefreshError?: (
    error: unknown,
    context: { speciesId: string; scientificName: string },
  ) => void;
}

interface InaturalistLookup {
  taxonId: number | null;
  resolution: "resolved" | "not_found" | "unavailable";
  providerErrors: string[];
}

interface ObservationSummary {
  total: number;
  lastObservedOn: string | null;
}

interface CoreStatsResult {
  lookup: InaturalistLookup;
  providerErrors: string[];
  summary: ObservationSummary;
  seasonality: SpeciesObservationMonthCount[];
  history: SpeciesObservationHistoryCount[];
  payload: SpeciesObservationStatsPayload;
}

interface ProviderBudget {
  deadlineAtMs: number;
  requestTimeoutMs: number;
  nowMs: () => number;
}

interface AnnotationValue {
  key: string;
  label: string;
  termId: number;
  valueId: number;
}

export const LIFE_STAGE_ANNOTATIONS: AnnotationValue[] = [
  { key: "adult", label: "Adult", termId: 1, valueId: 2 },
  { key: "teneral", label: "Teneral", termId: 1, valueId: 3 },
  { key: "pupa", label: "Pupa", termId: 1, valueId: 4 },
  { key: "nymph", label: "Nymph", termId: 1, valueId: 5 },
  { key: "larva", label: "Larva", termId: 1, valueId: 6 },
  { key: "egg", label: "Egg", termId: 1, valueId: 7 },
  { key: "juvenile", label: "Juvenile", termId: 1, valueId: 8 },
  { key: "subimago", label: "Subimago", termId: 1, valueId: 16 },
];

export const SEX_ANNOTATIONS: AnnotationValue[] = [
  { key: "female", label: "Female", termId: 9, valueId: 10 },
  { key: "male", label: "Male", termId: 9, valueId: 11 },
  {
    key: "cannot_determine",
    label: "Cannot determine",
    termId: 9,
    valueId: 20,
  },
];

export function parseSpeciesObservationStatsRequest(
  body: Record<string, unknown>,
): SpeciesObservationStatsRequestResult {
  const rawName = body.scientific_name;
  if (typeof rawName !== "string") {
    return {
      error: "Missing required parameter: scientific_name",
      status: 400,
    };
  }

  const scientificName = rawName.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return {
      error: "Missing required parameter: scientific_name",
      status: 400,
    };
  }

  if (scientificName.length > 160) {
    return { error: "scientific_name is too long.", status: 400 };
  }

  const rawSpeciesId = body.species_id;
  if (typeof rawSpeciesId !== "string") {
    return {
      error: "Missing required parameter: species_id",
      status: 400,
    };
  }

  const speciesId = rawSpeciesId.trim();
  if (!speciesId) {
    return {
      error: "Missing required parameter: species_id",
      status: 400,
    };
  }
  if (!isUuid(speciesId)) {
    return { error: "species_id must be a valid UUID.", status: 400 };
  }

  return { speciesId, scientificName };
}

export function parseSpeciesObservationStatsQuery(
  url: URL,
): SpeciesObservationStatsRequestResult {
  const body: Record<string, unknown> = {};
  const scientificName = url.searchParams.get("scientific_name");
  const speciesId = url.searchParams.get("species_id");

  if (scientificName !== null) {
    body.scientific_name = scientificName;
  }
  if (speciesId !== null) {
    body.species_id = speciesId;
  }

  return parseSpeciesObservationStatsRequest(body);
}

export async function fetchSpeciesObservationStats(
  request: { speciesId: string; scientificName: string },
  supabaseAdmin: SupabaseClient,
  options: SpeciesObservationStatsFetchOptions,
): Promise<SpeciesObservationStatsPayload> {
  const now = options.now ?? new Date();
  const authorized = await authorizeSpeciesObservationStatsRequest(
    request,
    options.securityContext,
    supabaseAdmin,
  );
  const resolvedSpeciesId = authorized.speciesId;
  const scientificName = authorized.scientificName;

  const cached = await fetchCachedStats(resolvedSpeciesId, supabaseAdmin);
  if (cached?.payload && isFresh(cached, now)) {
    return cached.payload;
  }

  if (cached?.payload && isStaleUsable(cached, now)) {
    if (options.runBackground) {
      try {
        const lease = await claimSpeciesObservationStatsPopulation(
          resolvedSpeciesId,
          options.securityContext,
          supabaseAdmin,
        );
        if (lease.claimed) {
          scheduleFullStatsRefresh(
            {
              speciesId: resolvedSpeciesId,
              scientificName,
              storedTaxonId: authorized.inaturalistTaxonId,
              lease,
            },
            supabaseAdmin,
            options,
            now,
          );
        }
      } catch (error) {
        options.onBackgroundRefreshError?.(error, {
          speciesId: resolvedSpeciesId,
          scientificName,
        });
      }
    }

    return {
      ...cached.payload,
      status: "stale",
    };
  }

  const lease = await claimSpeciesObservationStatsPopulation(
    resolvedSpeciesId,
    options.securityContext,
    supabaseAdmin,
  );
  if (lease.cacheAvailable) {
    const populated = await fetchCachedStats(resolvedSpeciesId, supabaseAdmin);
    if (populated?.payload && isFresh(populated, now)) {
      return populated.payload;
    }
    throw new SpeciesObservationStatsError(
      503,
      "species_stats_unavailable",
      "Species statistics are temporarily unavailable.",
      30,
    );
  }
  if (!lease.claimed || !lease.leaseToken) {
    throw new SpeciesObservationStatsError(
      503,
      "species_stats_refresh_in_progress",
      "Species statistics are being refreshed.",
      lease.retryAfterSeconds,
    );
  }

  const foregroundBudget = providerBudget(
    options,
    options.foregroundDeadlineMs ?? DEFAULT_FOREGROUND_DEADLINE_MS,
  );

  let core: CoreStatsResult;
  try {
    core = await fetchCoreStats(
      {
        speciesId: resolvedSpeciesId,
        scientificName,
        storedTaxonId: authorized.inaturalistTaxonId,
      },
      options,
      now,
      foregroundBudget,
    );
  } catch (error) {
    const unavailable = emptyStatsPayload({
      speciesId: resolvedSpeciesId,
      scientificName,
      taxonId: authorized.inaturalistTaxonId,
      now,
      status: "unavailable",
      providerErrors: [
        error instanceof Error ? error.message : String(error),
      ],
    });
    await finalizeLeasePayload(
      {
        speciesId: resolvedSpeciesId,
        scientificName,
        leaseToken: lease.leaseToken,
        payload: unavailable,
      },
      supabaseAdmin,
    );
    return unavailable;
  }

  if (!core.lookup.taxonId || !hasPayloadData(core.payload)) {
    await finalizeLeasePayload(
      {
        speciesId: resolvedSpeciesId,
        scientificName,
        leaseToken: lease.leaseToken,
        payload: core.payload,
      },
      supabaseAdmin,
    );
    return core.payload;
  }

  if (options.runBackground) {
    scheduleAnnotationRefreshFromCore(
      {
        speciesId: resolvedSpeciesId,
        leaseToken: lease.leaseToken,
        core,
      },
      supabaseAdmin,
      options,
      now,
    );
    return core.payload;
  }

  let payload: SpeciesObservationStatsPayload;
  try {
    payload = await completeStatsWithAnnotations(
      core,
      options,
      now,
      providerBudget(
        options,
        options.backgroundDeadlineMs ?? DEFAULT_BACKGROUND_DEADLINE_MS,
      ),
    );
  } catch (error) {
    payload = emptyStatsPayload({
      speciesId: resolvedSpeciesId,
      scientificName,
      taxonId: authorized.inaturalistTaxonId,
      now,
      status: "unavailable",
      providerErrors: [
        error instanceof Error ? error.message : String(error),
      ],
    });
  }
  await finalizeLeasePayload(
    {
      speciesId: resolvedSpeciesId,
      scientificName,
      leaseToken: lease.leaseToken,
      payload,
    },
    supabaseAdmin,
  );
  return payload;
}

export function normalizeMonthHistogram(
  json: unknown,
): SpeciesObservationMonthCount[] {
  const counts = histogramCounts(json);
  return Array.from({ length: 12 }, (_, index) => {
    const month = index + 1;
    return { month, count: counts.get(String(month)) ?? 0 };
  });
}

export function normalizeRollingHistoryHistogram(
  json: unknown,
  now: Date,
): SpeciesObservationHistoryCount[] {
  const counts = histogramCounts(json);
  const start = new Date(Date.UTC(now.getUTCFullYear() - 6, 0, 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const values: SpeciesObservationHistoryCount[] = [];

  for (
    let cursor = new Date(start);
    cursor <= end;
    cursor = new Date(
      Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1),
    )
  ) {
    const year = cursor.getUTCFullYear();
    const month = cursor.getUTCMonth() + 1;
    const key = `${year}-${String(month).padStart(2, "0")}`;
    values.push({ year, month, count: counts.get(key) ?? 0 });
  }

  return values;
}

export function buildAnnotationSeries(
  definitions: AnnotationValue[],
  histogramsByKey: Record<string, unknown>,
): SpeciesObservationCategorySeries[] {
  return definitions.map((definition) => ({
    key: definition.key,
    label: definition.label,
    values: normalizeMonthHistogram(histogramsByKey[definition.key] ?? {}),
  }));
}

export function histogramCounts(json: unknown): Map<string, number> {
  const candidate = histogramContainer(json);
  const counts = new Map<string, number>();
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return counts;
  }

  for (const [rawKey, rawValue] of Object.entries(candidate)) {
    const value = countValue(rawValue);
    if (value === null) continue;
    counts.set(rawKey, value);
  }

  return counts;
}

export function annotationLabelFor(
  termId: number,
  valueId: number,
): string | null {
  const match = [...LIFE_STAGE_ANNOTATIONS, ...SEX_ANNOTATIONS].find(
    (entry) => entry.termId === termId && entry.valueId === valueId,
  );
  return match?.label ?? null;
}

async function fetchCoreStats(
  request: {
    speciesId: string | null;
    scientificName: string;
    storedTaxonId: number | null;
  },
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
  budget: ProviderBudget,
): Promise<CoreStatsResult> {
  const fetcher = options.fetcher ?? fetch;
  const delayMs = options.delayMs ?? DEFAULT_DELAY_MS;
  const providerErrors: string[] = [];
  const lookup = await resolveInaturalistLookup(
    request.scientificName,
    request.storedTaxonId,
    fetcher,
    budget,
  );
  providerErrors.push(...lookup.providerErrors);

  if (!lookup.taxonId) {
    const status = lookup.resolution === "not_found"
      ? "no_data"
      : "unavailable";
    const payload = emptyStatsPayload({
      speciesId: request.speciesId,
      scientificName: request.scientificName,
      taxonId: null,
      now,
      status,
      providerErrors,
    });
    return {
      lookup,
      providerErrors,
      summary: { total: 0, lastObservedOn: null },
      seasonality: payload.seasonality,
      history: payload.history,
      payload,
    };
  }

  const summary = await safeProviderCall(
    () => fetchObservationSummary(lookup, fetcher, budget),
    providerErrors,
    { total: 0, lastObservedOn: null },
  );
  await sleepWithinBudget(delayMs, budget);

  const seasonality = await safeProviderCall(
    async () =>
      normalizeMonthHistogram(
        await fetchInaturalistJson(
          "/observations/histogram",
          {
            ...lookupParam(lookup),
            interval: "month_of_year",
            date_field: "observed",
            verifiable: "true",
          },
          fetcher,
          budget,
        ),
      ),
    providerErrors,
    emptyMonthCounts(),
  );
  await sleepWithinBudget(delayMs, budget);

  const history = await safeProviderCall(
    async () =>
      normalizeRollingHistoryHistogram(
        await fetchInaturalistJson(
          "/observations/histogram",
          {
            ...lookupParam(lookup),
            interval: "month",
            date_field: "observed",
            verifiable: "true",
            d1: `${now.getUTCFullYear() - 6}-01-01`,
            d2: isoDate(now),
          },
          fetcher,
          budget,
        ),
        now,
      ),
    providerErrors,
    normalizeRollingHistoryHistogram({}, now),
  );

  const hasData = summary.total > 0 ||
    hasAnyCounts(seasonality) ||
    hasAnyHistoryCounts(history);

  if (!hasData && providerErrors.length > 0) {
    throw new Error(dedupeStrings(providerErrors).join("; "));
  }

  const status: SpeciesObservationStatsPayload["status"] =
    providerErrors.length > 0 ? "partial" : hasData ? "partial" : "no_data";

  const payload = {
    species_id: request.speciesId,
    scientific_name: request.scientificName,
    source: {
      provider: "inaturalist" as const,
      scope: "global" as const,
      inaturalist_taxon_id: lookup.taxonId,
      fetched_at: now.toISOString(),
    },
    status,
    total_observations: summary.total,
    last_observation_date: summary.lastObservedOn,
    fetched_at: now.toISOString(),
    provider_errors: dedupeStrings(providerErrors),
    seasonality,
    history,
    life_stage: buildAnnotationSeries(LIFE_STAGE_ANNOTATIONS, {}),
    sex: buildAnnotationSeries(SEX_ANNOTATIONS, {}),
  };

  return { lookup, providerErrors, summary, seasonality, history, payload };
}

async function fetchFreshStats(
  request: {
    speciesId: string | null;
    scientificName: string;
    storedTaxonId: number | null;
  },
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
  budget: ProviderBudget,
): Promise<SpeciesObservationStatsPayload> {
  const core = await fetchCoreStats(
    request,
    options,
    now,
    budget,
  );

  if (!core.lookup.taxonId || !hasPayloadData(core.payload)) {
    return core.payload;
  }
  return await completeStatsWithAnnotations(core, options, now, budget);
}

async function completeStatsWithAnnotations(
  core: CoreStatsResult,
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
  budget: ProviderBudget,
): Promise<SpeciesObservationStatsPayload> {
  const fetcher = options.fetcher ?? fetch;
  const delayMs = options.delayMs ?? DEFAULT_DELAY_MS;
  const providerErrors = [...core.providerErrors];

  const lifeStage = await fetchAnnotationSeries(
    core.lookup,
    LIFE_STAGE_ANNOTATIONS,
    fetcher,
    providerErrors,
    delayMs,
    budget,
  );
  const sex = await fetchAnnotationSeries(
    core.lookup,
    SEX_ANNOTATIONS,
    fetcher,
    providerErrors,
    delayMs,
    budget,
  );

  const hasData = core.summary.total > 0 ||
    hasAnyCounts(core.seasonality) ||
    hasAnyHistoryCounts(core.history) ||
    lifeStage.some((series) => hasAnyCounts(series.values)) ||
    sex.some((series) => hasAnyCounts(series.values));

  if (!hasData && providerErrors.length > 0) {
    throw new Error(dedupeStrings(providerErrors).join("; "));
  }

  const status: SpeciesObservationStatsPayload["status"] =
    providerErrors.length > 0 ? "partial" : hasData ? "fresh" : "no_data";

  return {
    ...core.payload,
    source: {
      provider: "inaturalist",
      scope: "global",
      inaturalist_taxon_id: core.lookup.taxonId,
      fetched_at: now.toISOString(),
    },
    status,
    total_observations: core.summary.total,
    last_observation_date: core.summary.lastObservedOn,
    fetched_at: now.toISOString(),
    provider_errors: dedupeStrings(providerErrors),
    seasonality: core.seasonality,
    history: core.history,
    life_stage: lifeStage,
    sex,
  };
}

function scheduleAnnotationRefreshFromCore(
  input: {
    speciesId: string;
    leaseToken: string;
    core: CoreStatsResult;
  },
  supabaseAdmin: SupabaseClient,
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
): void {
  if (!options.runBackground) return;
  scheduleBackgroundRefresh(
    input.speciesId,
    input.core.payload.scientific_name,
    options,
    async () => {
      await Promise.resolve();
      const payload = await completeStatsWithAnnotations(
        input.core,
        options,
        now,
        providerBudget(
          options,
          options.backgroundDeadlineMs ?? DEFAULT_BACKGROUND_DEADLINE_MS,
        ),
      );
      await finalizeLeasePayload(
        {
          speciesId: input.speciesId,
          scientificName: input.core.payload.scientific_name,
          leaseToken: input.leaseToken,
          payload,
        },
        supabaseAdmin,
      );
    },
  );
}

function scheduleFullStatsRefresh(
  request: {
    speciesId: string;
    scientificName: string;
    storedTaxonId: number | null;
    lease: SpeciesObservationStatsPopulationLease;
  },
  supabaseAdmin: SupabaseClient,
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
): void {
  const leaseToken = request.lease.leaseToken;
  if (
    !options.runBackground ||
    !request.lease.claimed ||
    !leaseToken
  ) return;
  scheduleBackgroundRefresh(
    request.speciesId,
    request.scientificName,
    options,
    async () => {
      await Promise.resolve();
      let payload: SpeciesObservationStatsPayload;
      try {
        payload = await fetchFreshStats(
          {
            speciesId: request.speciesId,
            scientificName: request.scientificName,
            storedTaxonId: request.storedTaxonId,
          },
          options,
          now,
          providerBudget(
            options,
            options.backgroundDeadlineMs ?? DEFAULT_BACKGROUND_DEADLINE_MS,
          ),
        );
      } catch (error) {
        payload = emptyStatsPayload({
          speciesId: request.speciesId,
          scientificName: request.scientificName,
          taxonId: request.storedTaxonId,
          now,
          status: "unavailable",
          providerErrors: [
            error instanceof Error ? error.message : String(error),
          ],
        });
      }
      await finalizeLeasePayload(
        {
          speciesId: request.speciesId,
          scientificName: request.scientificName,
          leaseToken,
          payload,
        },
        supabaseAdmin,
      );
    },
  );
}

function scheduleBackgroundRefresh(
  cacheKey: string,
  scientificName: string,
  options: SpeciesObservationStatsFetchOptions,
  operation: () => Promise<void>,
): void {
  if (!options.runBackground) return;
  const task = operation()
    .catch((error) => {
      options.onBackgroundRefreshError?.(error, {
        speciesId: cacheKey,
        scientificName,
      });
    });
  options.runBackground(task);
}

async function fetchAnnotationSeries(
  lookup: InaturalistLookup,
  definitions: AnnotationValue[],
  fetcher: typeof fetch,
  providerErrors: string[],
  delayMs: number,
  budget: ProviderBudget,
): Promise<SpeciesObservationCategorySeries[]> {
  const histogramsByKey: Record<string, unknown> = {};
  for (const definition of definitions) {
    if (remainingBudgetMs(budget) <= 0) {
      providerErrors.push("iNaturalist population deadline exceeded");
      break;
    }
    histogramsByKey[definition.key] = await safeProviderCall(
      () =>
        fetchInaturalistJson(
          "/observations/histogram",
          {
            ...lookupParam(lookup),
            interval: "month_of_year",
            date_field: "observed",
            verifiable: "true",
            term_id: String(definition.termId),
            term_value_id: String(definition.valueId),
          },
          fetcher,
          budget,
        ),
      providerErrors,
      {},
    );
    await sleepWithinBudget(delayMs, budget);
  }
  return buildAnnotationSeries(definitions, histogramsByKey);
}

async function resolveInaturalistLookup(
  scientificName: string,
  storedTaxonId: number | null,
  fetcher: typeof fetch,
  budget: ProviderBudget,
): Promise<InaturalistLookup> {
  if (storedTaxonId && storedTaxonId > 0) {
    return {
      taxonId: storedTaxonId,
      resolution: "resolved",
      providerErrors: [],
    };
  }

  try {
    const json = await fetchInaturalistJson(
      "/taxa",
      { q: scientificName, per_page: "10" },
      fetcher,
      budget,
    );
    const taxonId = exactTaxonIdFromResponse(json, scientificName);
    if (taxonId) {
      return {
        taxonId,
        resolution: "resolved",
        providerErrors: [],
      };
    }
  } catch (error) {
    return {
      taxonId: null,
      resolution: "unavailable",
      providerErrors: [
        `iNaturalist taxon lookup failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      ],
    };
  }

  return {
    taxonId: null,
    resolution: "not_found",
    providerErrors: [
      `iNaturalist exact taxon match not found for ${scientificName}`,
    ],
  };
}

async function fetchObservationSummary(
  lookup: InaturalistLookup,
  fetcher: typeof fetch,
  budget: ProviderBudget,
): Promise<ObservationSummary> {
  const json = await fetchInaturalistJson(
    "/observations",
    {
      ...lookupParam(lookup),
      per_page: "1",
      order_by: "observed_on",
      order: "desc",
      verifiable: "true",
    },
    fetcher,
    budget,
  );
  const object = asObject(json);
  const total = numericValue(object?.total_results) ?? 0;
  const firstResult = Array.isArray(object?.results)
    ? asObject(object.results[0])
    : null;
  const lastObservedOn = stringValue(firstResult?.observed_on) ??
    stringValue(firstResult?.time_observed_at)?.slice(0, 10) ??
    null;
  return { total, lastObservedOn };
}

async function fetchInaturalistJson(
  path: string,
  params: Record<string, string>,
  fetcher: typeof fetch,
  budget: ProviderBudget,
): Promise<unknown> {
  const url = new URL(`${INAT_BASE_URL}${path}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const remainingMs = remainingBudgetMs(budget);
  if (remainingMs <= 0) {
    throw new Error("iNaturalist population deadline exceeded");
  }
  const timeoutMs = Math.max(
    1,
    Math.min(budget.requestTimeoutMs, remainingMs),
  );
  const signal = AbortSignal.timeout(timeoutMs);
  let response: Response;
  try {
    response = await fetcher(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": USER_AGENT,
      },
      signal,
    });
  } catch (error) {
    if (signal.aborted) {
      throw new Error(`iNaturalist ${path} timed out`);
    }
    throw error;
  }
  if (!response.ok) {
    throw new Error(`iNaturalist ${path} returned HTTP ${response.status}`);
  }
  const readResult = await readResponseArrayBufferWithinBudget(
    response,
    MAX_PROVIDER_RESPONSE_BYTES,
    `iNaturalist ${path} response exceeded the byte limit`,
  );
  if (readResult.error || !readResult.buffer) {
    throw new Error(
      readResult.error?.message ??
        `iNaturalist ${path} returned an unreadable response`,
    );
  }
  try {
    return JSON.parse(new TextDecoder().decode(readResult.buffer));
  } catch {
    throw new Error(`iNaturalist ${path} returned invalid JSON`);
  }
}

function lookupParam(lookup: InaturalistLookup): Record<string, string> {
  if (!lookup.taxonId) {
    throw new Error("A resolved iNaturalist taxon id is required");
  }
  return { taxon_id: String(lookup.taxonId) };
}

async function fetchCachedStats(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesStatsCacheRow | null> {
  const { data, error } = await supabaseAdmin
    .from("species_observation_stats_cache")
    .select("payload, status, fetched_at, expires_at, provider_error")
    .eq("species_id", speciesId)
    .eq("source", SOURCE)
    .eq("scope", SCOPE)
    .limit(1)
    .abortSignal(AbortSignal.timeout(DATABASE_TIMEOUT_MS));

  if (error) {
    throw new Error(`Failed to fetch species stats cache: ${error.message}`);
  }

  return ((data ?? []) as SpeciesStatsCacheRow[])[0] ?? null;
}

async function finalizeLeasePayload(
  input: {
    speciesId: string;
    scientificName: string;
    leaseToken: string;
    payload: SpeciesObservationStatsPayload;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (input.payload.status === "stale") {
    throw new Error("A stale payload cannot finalize a population lease");
  }
  const providerError = input.payload.provider_errors.length > 0
    ? input.payload.provider_errors.join("; ").slice(0, 1_000)
    : null;
  const finalized = await finalizeSpeciesObservationStatsPopulation(
    {
      speciesId: input.speciesId,
      leaseToken: input.leaseToken,
      taxonId: input.payload.source.inaturalist_taxon_id,
      payload: input.payload as unknown as Record<string, unknown>,
      status: input.payload.status,
      providerError,
    },
    supabaseAdmin,
  );
  if (!finalized) {
    throw new Error(
      `Species stats population lease was superseded for ${input.speciesId}`,
    );
  }
}

function providerBudget(
  options: SpeciesObservationStatsFetchOptions,
  durationMs: number,
): ProviderBudget {
  const nowMs = options.monotonicNowMs ?? (() => performance.now());
  const boundedDurationMs = Math.max(1, Math.min(durationMs, 60_000));
  const requestTimeoutMs = Math.max(
    1,
    Math.min(
      options.providerRequestTimeoutMs ?? DEFAULT_PROVIDER_REQUEST_TIMEOUT_MS,
      15_000,
    ),
  );
  return {
    deadlineAtMs: nowMs() + boundedDurationMs,
    requestTimeoutMs,
    nowMs,
  };
}

function remainingBudgetMs(budget: ProviderBudget): number {
  return Math.max(0, budget.deadlineAtMs - budget.nowMs());
}

async function sleepWithinBudget(
  milliseconds: number,
  budget: ProviderBudget,
): Promise<void> {
  if (milliseconds <= 0) return;
  const boundedDelay = Math.min(milliseconds, remainingBudgetMs(budget));
  if (boundedDelay <= 0) return;
  await new Promise((resolve) => setTimeout(resolve, boundedDelay));
}

async function safeProviderCall<T>(
  operation: () => Promise<T>,
  providerErrors: string[],
  fallback: T,
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    providerErrors.push(error instanceof Error ? error.message : String(error));
    return fallback;
  }
}

function emptyStatsPayload(
  input: {
    speciesId: string | null;
    scientificName: string;
    taxonId: number | null;
    now: Date;
    status: SpeciesObservationStatsPayload["status"];
    providerErrors?: string[];
  },
): SpeciesObservationStatsPayload {
  return {
    species_id: input.speciesId,
    scientific_name: input.scientificName,
    source: {
      provider: "inaturalist",
      scope: "global",
      inaturalist_taxon_id: input.taxonId,
      fetched_at: input.now.toISOString(),
    },
    status: input.status,
    total_observations: 0,
    last_observation_date: null,
    fetched_at: input.now.toISOString(),
    provider_errors: dedupeStrings(input.providerErrors ?? []),
    seasonality: emptyMonthCounts(),
    history: normalizeRollingHistoryHistogram({}, input.now),
    life_stage: buildAnnotationSeries(LIFE_STAGE_ANNOTATIONS, {}),
    sex: buildAnnotationSeries(SEX_ANNOTATIONS, {}),
  };
}

function histogramContainer(json: unknown): unknown {
  const object = asObject(json);
  if (!object) return null;
  if (object.results !== undefined) return object.results;
  if (object.results_by_month !== undefined) return object.results_by_month;
  return object;
}

function countValue(value: unknown): number | null {
  const direct = numericValue(value);
  if (direct !== null) return direct;

  const object = asObject(value);
  if (!object) return null;
  return numericValue(object.count) ??
    numericValue(object.total) ??
    numericValue(object.value) ??
    numericValue(object.observation_count);
}

function exactTaxonIdFromResponse(
  json: unknown,
  scientificName: string,
): number | null {
  const object = asObject(json);
  const results = Array.isArray(object?.results) ? object.results : [];
  const normalizedTarget = normalizeScientificName(scientificName)
    .toLowerCase();
  for (const item of results) {
    const row = asObject(item);
    const name = stringValue(row?.name);
    if (
      !name || normalizeScientificName(name).toLowerCase() !== normalizedTarget
    ) {
      continue;
    }
    const id = numericValue(row?.id);
    if (id && id > 0) return id;
  }
  return null;
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numericValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.round(value));
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.max(0, Math.round(parsed));
  }
  return null;
}

function isFresh(row: SpeciesStatsCacheRow, now: Date): boolean {
  const expiresAt = row.expires_at ? Date.parse(row.expires_at) : Number.NaN;
  return Number.isFinite(expiresAt) && expiresAt > now.getTime();
}

function isStaleUsable(row: SpeciesStatsCacheRow, now: Date): boolean {
  const fetchedAt = row.fetched_at ? Date.parse(row.fetched_at) : Number.NaN;
  if (!Number.isFinite(fetchedAt) || row.status === "unavailable") return false;
  const staleWindow = row.status === "no_data"
    ? NEGATIVE_STALE_TTL_MS
    : CACHE_TTL_MS + STALE_TTL_MS;
  return now.getTime() - fetchedAt <= staleWindow;
}

function emptyMonthCounts(): SpeciesObservationMonthCount[] {
  return Array.from({ length: 12 }, (_, index) => ({
    month: index + 1,
    count: 0,
  }));
}

function hasAnyCounts(values: SpeciesObservationMonthCount[]): boolean {
  return values.some((value) => value.count > 0);
}

function hasAnyHistoryCounts(
  values: SpeciesObservationHistoryCount[],
): boolean {
  return values.some((value) => value.count > 0);
}

function hasPayloadData(payload: SpeciesObservationStatsPayload): boolean {
  return payload.total_observations > 0 ||
    hasAnyCounts(payload.seasonality) ||
    hasAnyHistoryCounts(payload.history) ||
    payload.life_stage.some((series) => hasAnyCounts(series.values)) ||
    payload.sex.some((series) => hasAnyCounts(series.values));
}

function normalizeScientificName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of values) {
    const value = raw.trim();
    if (!value || seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }
  return result;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}
