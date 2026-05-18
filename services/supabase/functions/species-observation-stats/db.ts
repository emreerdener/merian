import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export const SPECIES_OBSERVATION_STATS_SCHEMA_VERSION = 1;
const INAT_BASE_URL = "https://api.inaturalist.org/v1";
const SOURCE = "inaturalist";
const SCOPE = "global";
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const STALE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const DEFAULT_DELAY_MS = 1000;
const USER_AGENT =
  "Merian/1.0 species-observation-stats (https://merian.app; public-cache)";

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

interface SpeciesDictionaryStatsRow {
  id?: string | null;
  scientific_name?: string | null;
  inaturalist_taxon_id?: number | null;
}

interface SpeciesStatsCacheRow {
  payload?: SpeciesObservationStatsPayload | null;
  status?: SpeciesObservationStatsPayload["status"] | null;
  fetched_at?: string | null;
  expires_at?: string | null;
  provider_error?: string | null;
}

export interface SpeciesObservationStatsFetchOptions {
  fetcher?: typeof fetch;
  now?: Date;
  delayMs?: number;
}

interface InaturalistLookup {
  taxonId: number | null;
  paramName: "taxon_id" | "taxon_name";
  paramValue: string;
  providerErrors: string[];
}

interface ObservationSummary {
  total: number;
  lastObservedOn: string | null;
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
  if (rawSpeciesId === undefined || rawSpeciesId === null) {
    return { scientificName };
  }

  if (typeof rawSpeciesId !== "string") {
    return { error: "species_id must be a valid UUID.", status: 400 };
  }

  const speciesId = rawSpeciesId.trim();
  if (!speciesId) return { scientificName };
  if (!isUuid(speciesId)) {
    return { error: "species_id must be a valid UUID.", status: 400 };
  }

  return { speciesId, scientificName };
}

export async function fetchSpeciesObservationStats(
  request: { speciesId?: string; scientificName: string },
  supabaseAdmin: SupabaseClient,
  options: SpeciesObservationStatsFetchOptions = {},
): Promise<SpeciesObservationStatsPayload> {
  const now = options.now ?? new Date();
  const row = await fetchSpeciesRow(request, supabaseAdmin);
  const resolvedSpeciesId = row?.id ?? request.speciesId ?? null;
  const scientificName = normalizeScientificName(
    row?.scientific_name ?? request.scientificName,
  );

  const cached = row?.id ? await fetchCachedStats(row.id, supabaseAdmin) : null;
  if (cached?.payload && isFresh(cached, now)) {
    return cached.payload;
  }

  try {
    const payload = await fetchFreshStats(
      {
        speciesId: resolvedSpeciesId,
        scientificName,
        storedTaxonId: row?.inaturalist_taxon_id ?? null,
      },
      supabaseAdmin,
      options,
      now,
    );

    if (row?.id) {
      await upsertCachedStats(row.id, scientificName, payload, supabaseAdmin);
    }

    return payload;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (cached?.payload && isStaleUsable(cached, now)) {
      return {
        ...cached.payload,
        status: "stale",
        provider_errors: dedupeStrings([
          ...cached.payload.provider_errors,
          message,
        ]),
      };
    }

    return emptyStatsPayload({
      speciesId: resolvedSpeciesId,
      scientificName,
      taxonId: row?.inaturalist_taxon_id ?? null,
      now,
      status: "unavailable",
      providerErrors: [message],
    });
  }
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

async function fetchFreshStats(
  request: {
    speciesId: string | null;
    scientificName: string;
    storedTaxonId: number | null;
  },
  supabaseAdmin: SupabaseClient,
  options: SpeciesObservationStatsFetchOptions,
  now: Date,
): Promise<SpeciesObservationStatsPayload> {
  const fetcher = options.fetcher ?? fetch;
  const delayMs = options.delayMs ?? DEFAULT_DELAY_MS;
  const providerErrors: string[] = [];
  const lookup = await resolveInaturalistLookup(
    request.scientificName,
    request.storedTaxonId,
    fetcher,
  );
  providerErrors.push(...lookup.providerErrors);

  if (
    request.speciesId && lookup.taxonId &&
    lookup.taxonId !== request.storedTaxonId
  ) {
    await updateTaxonId(request.speciesId, lookup.taxonId, supabaseAdmin);
  }

  const summary = await safeProviderCall(
    () => fetchObservationSummary(lookup, fetcher),
    providerErrors,
    { total: 0, lastObservedOn: null },
  );
  await sleep(delayMs);

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
        ),
      ),
    providerErrors,
    emptyMonthCounts(),
  );
  await sleep(delayMs);

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
        ),
        now,
      ),
    providerErrors,
    normalizeRollingHistoryHistogram({}, now),
  );

  const lifeStage = await fetchAnnotationSeries(
    lookup,
    LIFE_STAGE_ANNOTATIONS,
    fetcher,
    providerErrors,
    delayMs,
  );
  const sex = await fetchAnnotationSeries(
    lookup,
    SEX_ANNOTATIONS,
    fetcher,
    providerErrors,
    delayMs,
  );

  const hasData = summary.total > 0 ||
    hasAnyCounts(seasonality) ||
    hasAnyHistoryCounts(history) ||
    lifeStage.some((series) => hasAnyCounts(series.values)) ||
    sex.some((series) => hasAnyCounts(series.values));

  if (!hasData && looksLikeProviderOutage(providerErrors)) {
    throw new Error(dedupeStrings(providerErrors).join("; "));
  }

  const status = providerErrors.length > 0
    ? "partial"
    : hasData
    ? "fresh"
    : "no_data";

  return {
    species_id: request.speciesId,
    scientific_name: request.scientificName,
    source: {
      provider: "inaturalist",
      scope: "global",
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
    life_stage: lifeStage,
    sex,
  };
}

async function fetchAnnotationSeries(
  lookup: InaturalistLookup,
  definitions: AnnotationValue[],
  fetcher: typeof fetch,
  providerErrors: string[],
  delayMs: number,
): Promise<SpeciesObservationCategorySeries[]> {
  const histogramsByKey: Record<string, unknown> = {};
  for (const definition of definitions) {
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
        ),
      providerErrors,
      {},
    );
    await sleep(delayMs);
  }
  return buildAnnotationSeries(definitions, histogramsByKey);
}

async function resolveInaturalistLookup(
  scientificName: string,
  storedTaxonId: number | null,
  fetcher: typeof fetch,
): Promise<InaturalistLookup> {
  if (storedTaxonId && storedTaxonId > 0) {
    return {
      taxonId: storedTaxonId,
      paramName: "taxon_id",
      paramValue: String(storedTaxonId),
      providerErrors: [],
    };
  }

  try {
    const json = await fetchInaturalistJson(
      "/taxa",
      { q: scientificName, per_page: "10" },
      fetcher,
    );
    const taxonId = exactTaxonIdFromResponse(json, scientificName);
    if (taxonId) {
      return {
        taxonId,
        paramName: "taxon_id",
        paramValue: String(taxonId),
        providerErrors: [],
      };
    }
  } catch (error) {
    return {
      taxonId: null,
      paramName: "taxon_name",
      paramValue: scientificName,
      providerErrors: [
        `iNaturalist taxon lookup failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      ],
    };
  }

  return {
    taxonId: null,
    paramName: "taxon_name",
    paramValue: scientificName,
    providerErrors: [
      `iNaturalist exact taxon match not found for ${scientificName}`,
    ],
  };
}

async function fetchObservationSummary(
  lookup: InaturalistLookup,
  fetcher: typeof fetch,
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
): Promise<unknown> {
  const url = new URL(`${INAT_BASE_URL}${path}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetcher(url, {
    headers: {
      Accept: "application/json",
      "User-Agent": USER_AGENT,
    },
  });
  if (!response.ok) {
    throw new Error(`iNaturalist ${path} returned HTTP ${response.status}`);
  }
  return await response.json();
}

function lookupParam(lookup: InaturalistLookup): Record<string, string> {
  return { [lookup.paramName]: lookup.paramValue };
}

async function fetchSpeciesRow(
  request: { speciesId?: string; scientificName: string },
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryStatsRow | null> {
  const query = supabaseAdmin
    .from("species_dictionary")
    .select("id, scientific_name, inaturalist_taxon_id")
    .limit(1);

  const { data, error } = request.speciesId
    ? await query.eq("id", request.speciesId)
    : await query.eq("scientific_name", request.scientificName);

  if (error) {
    throw new Error(`Failed to fetch species dictionary row: ${error.message}`);
  }

  return ((data ?? []) as SpeciesDictionaryStatsRow[])[0] ?? null;
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
    .limit(1);

  if (error) {
    throw new Error(`Failed to fetch species stats cache: ${error.message}`);
  }

  return ((data ?? []) as SpeciesStatsCacheRow[])[0] ?? null;
}

async function upsertCachedStats(
  speciesId: string,
  scientificName: string,
  payload: SpeciesObservationStatsPayload,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const fetchedAt = new Date(payload.fetched_at);
  const expiresAt = new Date(fetchedAt.getTime() + CACHE_TTL_MS);
  const providerError = payload.provider_errors.length > 0
    ? payload.provider_errors.join("; ")
    : null;

  const { error } = await supabaseAdmin
    .from("species_observation_stats_cache")
    .upsert(
      {
        species_id: speciesId,
        source: SOURCE,
        scope: SCOPE,
        scientific_name: scientificName,
        payload,
        status: payload.status,
        provider_error: providerError,
        fetched_at: payload.fetched_at,
        expires_at: expiresAt.toISOString(),
      },
      { onConflict: "species_id,source,scope" },
    );

  if (error) {
    throw new Error(`Failed to upsert species stats cache: ${error.message}`);
  }
}

async function updateTaxonId(
  speciesId: string,
  taxonId: number,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("species_dictionary")
    .update({ inaturalist_taxon_id: taxonId })
    .eq("id", speciesId);
  if (error) {
    throw new Error(`Failed to update iNaturalist taxon id: ${error.message}`);
  }
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
  return Number.isFinite(fetchedAt) &&
    now.getTime() - fetchedAt <= CACHE_TTL_MS + STALE_TTL_MS;
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

function looksLikeProviderOutage(providerErrors: string[]): boolean {
  return providerErrors.some((error) => {
    const normalized = error.toLowerCase();
    return normalized.includes("http") ||
      normalized.includes("network") ||
      normalized.includes("fetch") ||
      normalized.includes("timed out") ||
      normalized.includes("connection");
  });
}

function normalizeScientificName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function sleep(milliseconds: number): Promise<void> {
  if (milliseconds <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
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
