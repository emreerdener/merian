import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  annotationLabelFor,
  buildAnnotationSeries,
  fetchSpeciesObservationStats,
  histogramCounts,
  normalizeMonthHistogram,
  normalizeRollingHistoryHistogram,
  parseSpeciesObservationStatsQuery,
  parseSpeciesObservationStatsRequest,
  type SpeciesObservationStatsPayload,
} from "./db.ts";
import { SpeciesObservationStatsError } from "./security.ts";

const SPECIES_ID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01";
const LEASE_TOKEN = "00000000-0000-4000-8000-000000000901";
const SECURITY_CONTEXT = {
  userId: "00000000-0000-4000-8000-000000000902",
  ipHash: "a".repeat(64),
};

Deno.test("species-observation-stats validates request body", () => {
  assertEquals(
    parseSpeciesObservationStatsRequest({
      species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientific_name: "  Danaus   plexippus  ",
    }),
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
  );

  assertEquals(
    parseSpeciesObservationStatsRequest({
      scientific_name: "Danaus plexippus",
    }),
    {
      error: "Missing required parameter: species_id",
      status: 400,
    },
  );

  assertEquals(parseSpeciesObservationStatsRequest({}), {
    error: "Missing required parameter: scientific_name",
    status: 400,
  });

  assertEquals(
    parseSpeciesObservationStatsRequest({
      species_id: "not-a-uuid",
      scientific_name: "Danaus plexippus",
    }),
    {
      error: "species_id must be a valid UUID.",
      status: 400,
    },
  );
});

Deno.test("species-observation-stats validates GET query parameters", () => {
  assertEquals(
    parseSpeciesObservationStatsQuery(
      new URL(
        "https://example.com/functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=%20Danaus%20%20%20plexippus%20",
      ),
    ),
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
  );

  assertEquals(
    parseSpeciesObservationStatsQuery(
      new URL("https://example.com/functions/v1/species-observation-stats"),
    ),
    {
      error: "Missing required parameter: scientific_name",
      status: 400,
    },
  );

  assertEquals(
    parseSpeciesObservationStatsQuery(
      new URL(
        "https://example.com/functions/v1/species-observation-stats?scientific_name=Danaus%20plexippus",
      ),
    ),
    {
      error: "Missing required parameter: species_id",
      status: 400,
    },
  );
});

Deno.test("species-observation-stats normalizes iNaturalist month buckets", () => {
  assertEquals(
    normalizeMonthHistogram({
      results: {
        "1": 4,
        "2": { count: 7 },
        "12": { total: "9" },
        "13": 12,
      },
    }),
    [
      { month: 1, count: 4 },
      { month: 2, count: 7 },
      { month: 3, count: 0 },
      { month: 4, count: 0 },
      { month: 5, count: 0 },
      { month: 6, count: 0 },
      { month: 7, count: 0 },
      { month: 8, count: 0 },
      { month: 9, count: 0 },
      { month: 10, count: 0 },
      { month: 11, count: 0 },
      { month: 12, count: 9 },
    ],
  );
});

Deno.test("species-observation-stats normalizes rolling seven-year history", () => {
  const values = normalizeRollingHistoryHistogram(
    {
      results: {
        "2020-01": 2,
        "2025-08": { count: 44 },
        "2026-05": "5",
      },
    },
    new Date("2026-05-17T12:00:00Z"),
  );

  assertEquals(values.length, 77);
  assertEquals(values[0], { year: 2020, month: 1, count: 2 });
  assertEquals(
    values.find((value) => value.year === 2025 && value.month === 8),
    {
      year: 2025,
      month: 8,
      count: 44,
    },
  );
  assertEquals(values[76], { year: 2026, month: 5, count: 5 });
});

Deno.test("species-observation-stats maps annotation value ids", () => {
  assertEquals(annotationLabelFor(1, 2), "Adult");
  assertEquals(annotationLabelFor(1, 7), "Egg");
  assertEquals(annotationLabelFor(9, 10), "Female");
  assertEquals(annotationLabelFor(9, 11), "Male");
  assertEquals(annotationLabelFor(9, 999), null);
});

Deno.test("species-observation-stats builds annotation series from histograms", () => {
  const series = buildAnnotationSeries(
    [
      { key: "adult", label: "Adult", termId: 1, valueId: 2 },
      { key: "egg", label: "Egg", termId: 1, valueId: 7 },
    ],
    {
      adult: { results: { "6": 12, "7": 30 } },
      egg: { results: { "4": 3 } },
    },
  );

  assertEquals(series[0].key, "adult");
  assertEquals(series[0].values[5], { month: 6, count: 12 });
  assertEquals(series[1].values[3], { month: 4, count: 3 });
});

Deno.test("species-observation-stats reads resilient histogram count shapes", () => {
  assertEquals(
    Array.from(
      histogramCounts({
        results: {
          "2026-01": { observation_count: 8 },
          "2026-02": { value: 4 },
          "2026-03": { ignored: true },
        },
      }).entries(),
    ),
    [
      ["2026-01", 8],
      ["2026-02", 4],
    ],
  );
});

Deno.test("species-observation-stats returns fresh cache without provider calls", async () => {
  const payload = {
    species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    scientific_name: "Danaus plexippus",
    source: {
      provider: "inaturalist" as const,
      scope: "global" as const,
      inaturalist_taxon_id: 48662,
      fetched_at: "2026-05-17T00:00:00.000Z",
    },
    status: "fresh" as const,
    total_observations: 42,
    last_observation_date: "2026-05-16",
    fetched_at: "2026-05-17T00:00:00.000Z",
    provider_errors: [],
    seasonality: normalizeMonthHistogram({ results: { "5": 42 } }),
    history: normalizeRollingHistoryHistogram(
      {},
      new Date("2026-05-17T00:00:00Z"),
    ),
    life_stage: [],
    sex: [],
  };
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [
      {
        species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        source: "inaturalist",
        scope: "global",
        payload,
        status: "fresh",
        fetched_at: "2026-05-17T00:00:00.000Z",
        expires_at: "2026-05-20T00:00:00.000Z",
      },
    ],
  });

  const result = await fetchSpeciesObservationStats(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      now: new Date("2026-05-17T12:00:00Z"),
      delayMs: 0,
      fetcher: (() => {
        providerCalls += 1;
        return Promise.resolve(new Response("{}"));
      }) as typeof fetch,
    },
  );

  assertEquals(result.total_observations, 42);
  assertEquals(providerCalls, 0);
});

Deno.test("species-observation-stats returns core stats and refreshes annotations in background", async () => {
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [],
  });
  const state = (fakeSupabase as unknown as {
    state: { upserts: Array<Record<string, unknown>> };
  }).state;
  const backgroundTasks: Promise<void>[] = [];

  const result = await fetchSpeciesObservationStats(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      now: new Date("2026-05-17T12:00:00Z"),
      delayMs: 0,
      fetcher: mockInatFetcherWithAnnotations,
      runBackground: (task) => backgroundTasks.push(task),
    },
  );

  assertEquals(result.status, "partial");
  assertEquals(result.total_observations, 12);
  assertEquals(
    result.life_stage[0].values.every((value) => value.count === 0),
    true,
  );
  assertEquals(backgroundTasks.length, 1);

  await backgroundTasks[0];

  assertEquals(state.upserts.length, 1);
  const cachedPayload = state.upserts[0]
    .payload as SpeciesObservationStatsPayload;
  assertEquals(cachedPayload.status, "fresh");
  assertEquals(cachedPayload.life_stage[0].key, "adult");
  assertEquals(cachedPayload.life_stage[0].values[5], { month: 6, count: 4 });
  assertEquals(cachedPayload.sex[1].key, "male");
  assertEquals(cachedPayload.sex[1].values[6], { month: 7, count: 2 });
});

Deno.test("species-observation-stats returns stale cache without blocking on refresh", async () => {
  const payload = {
    species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    scientific_name: "Danaus plexippus",
    source: {
      provider: "inaturalist" as const,
      scope: "global" as const,
      inaturalist_taxon_id: 48662,
      fetched_at: "2026-05-01T00:00:00.000Z",
    },
    status: "fresh" as const,
    total_observations: 10,
    last_observation_date: "2026-05-01",
    fetched_at: "2026-05-01T00:00:00.000Z",
    provider_errors: [],
    seasonality: normalizeMonthHistogram({ results: { "5": 10 } }),
    history: normalizeRollingHistoryHistogram(
      {},
      new Date("2026-05-01T00:00:00Z"),
    ),
    life_stage: [],
    sex: [],
  };
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [
      {
        species_id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        source: "inaturalist",
        scope: "global",
        payload,
        status: "fresh",
        fetched_at: "2026-05-01T00:00:00.000Z",
        expires_at: "2026-05-08T00:00:00.000Z",
      },
    ],
  });

  const result = await fetchSpeciesObservationStats(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      now: new Date("2026-05-17T12:00:00Z"),
      delayMs: 0,
      fetcher: (() => Promise.resolve(jsonResponse({}, 503))) as typeof fetch,
    },
  );

  assertEquals(result.status, "stale");
  assertEquals(result.total_observations, 10);
  assertEquals(result.provider_errors.length, 0);
});

Deno.test("species-observation-stats marks partial provider failures", async () => {
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: null,
      },
    ],
    cacheRows: [],
  });

  const result = await fetchSpeciesObservationStats(
    {
      speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
      scientificName: "Danaus plexippus",
    },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      now: new Date("2026-05-17T12:00:00Z"),
      delayMs: 0,
      fetcher: mockInatFetcherWithSeasonalityFailure,
    },
  );

  assertEquals(result.status, "partial");
  assertEquals(result.total_observations, 12);
  assertEquals(result.source.inaturalist_taxon_id, 48662);
  assertEquals(result.seasonality.every((value) => value.count === 0), true);
});

Deno.test("species-observation-stats treats empty failed core population as unavailable", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [],
  });
  const state = (fakeSupabase as unknown as {
    state: { upserts: Array<Record<string, unknown>> };
  }).state;

  const result = await fetchSpeciesObservationStats(
    {
      speciesId: SPECIES_ID,
      scientificName: "Danaus plexippus",
    },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      now: new Date("2026-05-17T12:00:00Z"),
      delayMs: 0,
      fetcher: (() => {
        providerCalls += 1;
        return Promise.resolve(
          new Response("{not-json", {
            headers: { "Content-Type": "application/json" },
          }),
        );
      }) as typeof fetch,
    },
  );

  assertEquals(result.status, "unavailable");
  assertEquals(result.total_observations, 0);
  assertEquals(providerCalls, 3);
  assertEquals(state.upserts.length, 1);
  assertEquals(state.upserts[0]?.status, "unavailable");
});

Deno.test("species-observation-stats rejects non-canonical dictionary requests before provider work", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [],
  });

  const error = await assertRejects(
    () =>
      fetchSpeciesObservationStats(
        {
          speciesId: SPECIES_ID,
          scientificName: "Attacker supplied name",
        },
        fakeSupabase,
        {
          securityContext: SECURITY_CONTEXT,
          delayMs: 0,
          fetcher: (() => {
            providerCalls += 1;
            return Promise.resolve(jsonResponse({}));
          }) as typeof fetch,
        },
      ),
    SpeciesObservationStatsError,
  );

  assertEquals(error.status, 404);
  assertEquals(error.code, "species_stats_species_not_found");
  assertEquals(providerCalls, 0);
});

Deno.test("species-observation-stats negatively caches an exact taxon miss", async () => {
  let providerCalls = 0;
  const requestedUrls: URL[] = [];
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Unmapped testus",
        inaturalist_taxon_id: null,
      },
    ],
    cacheRows: [],
  });
  const fetcher = ((input: URL | Request | string) => {
    providerCalls += 1;
    const url = input instanceof URL
      ? input
      : new URL(input instanceof Request ? input.url : String(input));
    requestedUrls.push(url);
    return Promise.resolve(
      jsonResponse({ results: [{ id: 12, name: "Different testus" }] }),
    );
  }) as typeof fetch;
  const options = {
    securityContext: SECURITY_CONTEXT,
    now: new Date("2026-05-17T12:00:00Z"),
    delayMs: 0,
    fetcher,
  };

  const first = await fetchSpeciesObservationStats(
    { speciesId: SPECIES_ID, scientificName: "Unmapped testus" },
    fakeSupabase,
    options,
  );
  const second = await fetchSpeciesObservationStats(
    { speciesId: SPECIES_ID, scientificName: "Unmapped testus" },
    fakeSupabase,
    options,
  );

  assertEquals(first.status, "no_data");
  assertEquals(second.status, "no_data");
  assertEquals(providerCalls, 1);
  assertEquals(requestedUrls[0]?.pathname.endsWith("/taxa"), true);
  assertEquals(requestedUrls[0]?.searchParams.get("q"), "Unmapped testus");
  assertEquals(
    requestedUrls.some((url) => url.pathname.endsWith("/observations")),
    false,
  );
});

Deno.test("species-observation-stats does not downgrade and retry failed finalization", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Unmapped testus",
        inaturalist_taxon_id: null,
      },
    ],
    cacheRows: [],
    finalizeError: "database unavailable",
  });
  const state = (fakeSupabase as unknown as {
    state: {
      rpcCalls: Array<{ name: string; args: Record<string, unknown> }>;
    };
  }).state;

  const error = await assertRejects(
    () =>
      fetchSpeciesObservationStats(
        { speciesId: SPECIES_ID, scientificName: "Unmapped testus" },
        fakeSupabase,
        {
          securityContext: SECURITY_CONTEXT,
          now: new Date("2026-05-17T12:00:00Z"),
          delayMs: 0,
          fetcher: (() => {
            providerCalls += 1;
            return Promise.resolve(jsonResponse({ results: [] }));
          }) as typeof fetch,
        },
      ),
    SpeciesObservationStatsError,
  );

  const finalizations = state.rpcCalls.filter((call) =>
    call.name === "finalize_species_observation_stats_population"
  );
  assertEquals(error.code, "species_stats_unavailable");
  assertEquals(providerCalls, 1);
  assertEquals(finalizations.length, 1);
  assertEquals(finalizations[0].args.p_status, "no_data");
});

Deno.test("species-observation-stats does no provider work without the distributed lease", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [],
    claimResult: {
      claimed: false,
      leaseToken: null,
      retryAfterSeconds: 45,
      cacheAvailable: false,
    },
  });

  const error = await assertRejects(
    () =>
      fetchSpeciesObservationStats(
        {
          speciesId: SPECIES_ID,
          scientificName: "Danaus plexippus",
        },
        fakeSupabase,
        {
          securityContext: SECURITY_CONTEXT,
          delayMs: 0,
          fetcher: (() => {
            providerCalls += 1;
            return Promise.resolve(jsonResponse({}));
          }) as typeof fetch,
        },
      ),
    SpeciesObservationStatsError,
  );

  assertEquals(error.code, "species_stats_refresh_in_progress");
  assertEquals(error.retryAfterSeconds, 45);
  assertEquals(providerCalls, 0);
});

Deno.test("species-observation-stats applies an AbortSignal to every provider request", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Danaus plexippus",
        inaturalist_taxon_id: 48662,
      },
    ],
    cacheRows: [],
  });
  const fetcher = ((
    input: URL | Request | string,
    init?: RequestInit,
  ) => {
    providerCalls += 1;
    assert(init?.signal instanceof AbortSignal);
    return mockInatFetcherWithAnnotations(input);
  }) as typeof fetch;

  const result = await fetchSpeciesObservationStats(
    { speciesId: SPECIES_ID, scientificName: "Danaus plexippus" },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      delayMs: 0,
      fetcher,
      providerRequestTimeoutMs: 250,
    },
  );

  assertEquals(result.status, "fresh");
  assertEquals(providerCalls, 14);
});

Deno.test("species-observation-stats bounds provider response bodies", async () => {
  let providerCalls = 0;
  const fakeSupabase = makeFakeSupabase({
    speciesRows: [
      {
        id: SPECIES_ID,
        scientific_name: "Oversized testus",
        inaturalist_taxon_id: null,
      },
    ],
    cacheRows: [],
  });

  const result = await fetchSpeciesObservationStats(
    { speciesId: SPECIES_ID, scientificName: "Oversized testus" },
    fakeSupabase,
    {
      securityContext: SECURITY_CONTEXT,
      delayMs: 0,
      fetcher: (() => {
        providerCalls += 1;
        return Promise.resolve(
          new Response(
            JSON.stringify({ padding: "x".repeat(1024 * 1024) }),
            { headers: { "Content-Type": "application/json" } },
          ),
        );
      }) as typeof fetch,
    },
  );

  assertEquals(result.status, "unavailable");
  assertEquals(providerCalls, 1);
  assertEquals(
    result.provider_errors.some((message) =>
      message.includes("response exceeded the byte limit")
    ),
    true,
  );
});

function mockInatFetcherWithSeasonalityFailure(
  input: URL | Request | string,
): Promise<Response> {
  const url = input instanceof URL
    ? input
    : new URL(input instanceof Request ? input.url : String(input));

  if (url.pathname.endsWith("/taxa")) {
    return Promise.resolve(
      jsonResponse({ results: [{ id: 48662, name: "Danaus plexippus" }] }),
    );
  }

  if (url.pathname.endsWith("/observations")) {
    return Promise.resolve(jsonResponse({
      total_results: 12,
      results: [{ observed_on: "2026-05-16" }],
    }));
  }

  if (
    url.searchParams.get("interval") === "month_of_year" &&
    !url.searchParams.has("term_id")
  ) {
    return Promise.resolve(jsonResponse({}, 503));
  }

  if (url.searchParams.get("interval") === "month") {
    return Promise.resolve(jsonResponse({ results: { "2026-05": 12 } }));
  }

  return Promise.resolve(jsonResponse({ results: {} }));
}

function mockInatFetcherWithAnnotations(
  input: URL | Request | string,
): Promise<Response> {
  const url = input instanceof URL
    ? input
    : new URL(input instanceof Request ? input.url : String(input));

  if (url.pathname.endsWith("/observations")) {
    return Promise.resolve(jsonResponse({
      total_results: 12,
      results: [{ observed_on: "2026-05-16" }],
    }));
  }

  if (url.searchParams.get("interval") === "month") {
    return Promise.resolve(jsonResponse({ results: { "2026-05": 12 } }));
  }

  if (
    url.searchParams.get("interval") === "month_of_year" &&
    !url.searchParams.has("term_id")
  ) {
    return Promise.resolve(jsonResponse({ results: { "5": 12 } }));
  }

  if (
    url.searchParams.get("term_id") === "1" &&
    url.searchParams.get("term_value_id") === "2"
  ) {
    return Promise.resolve(jsonResponse({ results: { "6": 4 } }));
  }

  if (
    url.searchParams.get("term_id") === "9" &&
    url.searchParams.get("term_value_id") === "11"
  ) {
    return Promise.resolve(jsonResponse({ results: { "7": 2 } }));
  }

  return Promise.resolve(jsonResponse({ results: {} }));
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function makeFakeSupabase(input: {
  speciesRows: Array<Record<string, unknown>>;
  cacheRows: Array<Record<string, unknown>>;
  finalizeError?: string;
  claimResult?: {
    claimed: boolean;
    leaseToken?: string | null;
    retryAfterSeconds?: number;
    cacheAvailable?: boolean;
  };
}) {
  const state = {
    speciesRows: input.speciesRows,
    cacheRows: input.cacheRows,
    upserts: [] as Array<Record<string, unknown>>,
    updates: [] as Array<Record<string, unknown>>,
    rpcCalls: [] as Array<{
      name: string;
      args: Record<string, unknown>;
    }>,
  };
  return {
    state,
    from(table: string) {
      return new FakeQuery(table, state);
    },
    rpc(name: string, args: Record<string, unknown>) {
      state.rpcCalls.push({ name, args });
      return {
        abortSignal: () => {
          if (name === "authorize_species_observation_stats_request") {
            const speciesRow = state.speciesRows.find((row) =>
              row.id === args.p_species_id
            );
            const requestedName = String(args.p_scientific_name ?? "")
              .trim()
              .replace(/\s+/g, " ");
            const canonicalName = String(
              speciesRow?.scientific_name ?? "",
            ).trim().replace(/\s+/g, " ");
            if (
              !speciesRow ||
              requestedName.toLowerCase() !== canonicalName.toLowerCase()
            ) {
              return Promise.resolve({
                data: [{
                  species_id: null,
                  scientific_name: null,
                  inaturalist_taxon_id: null,
                  denial_code: "species_stats_species_not_found",
                }],
                error: null,
              });
            }
            return Promise.resolve({
              data: [{
                species_id: speciesRow.id,
                scientific_name: canonicalName,
                inaturalist_taxon_id: speciesRow.inaturalist_taxon_id ?? null,
                denial_code: null,
              }],
              error: null,
            });
          }

          if (name === "claim_species_observation_stats_population") {
            const claim = input.claimResult ?? {
              claimed: true,
              leaseToken: LEASE_TOKEN,
              retryAfterSeconds: 90,
              cacheAvailable: false,
            };
            return Promise.resolve({
              data: [{
                claimed: claim.claimed,
                lease_token: claim.claimed
                  ? claim.leaseToken ?? LEASE_TOKEN
                  : null,
                lease_expires_at: "2026-05-17T12:01:30.000Z",
                retry_after_seconds: claim.retryAfterSeconds ?? 90,
                cache_available: claim.cacheAvailable ?? false,
              }],
              error: null,
            });
          }

          if (name === "finalize_species_observation_stats_population") {
            if (input.finalizeError) {
              return Promise.resolve({
                data: null,
                error: { message: input.finalizeError },
              });
            }
            const payload = args.p_payload as SpeciesObservationStatsPayload;
            state.upserts.push({
              species_id: args.p_species_id,
              payload,
              status: args.p_status,
            });
            state.cacheRows = state.cacheRows.filter((row) =>
              row.species_id !== args.p_species_id
            );
            state.cacheRows.push({
              species_id: args.p_species_id,
              source: "inaturalist",
              scope: "global",
              payload,
              status: args.p_status,
              fetched_at: payload.fetched_at,
              expires_at: new Date(
                Date.parse(payload.fetched_at) +
                  (args.p_status === "no_data"
                    ? 24 * 60 * 60 * 1000
                    : args.p_status === "unavailable"
                    ? 5 * 60 * 1000
                    : 7 * 24 * 60 * 60 * 1000),
              ).toISOString(),
            });
            return Promise.resolve({ data: true, error: null });
          }

          return Promise.resolve({
            data: null,
            error: { message: `Unexpected RPC: ${name}` },
          });
        },
      };
    },
  } as unknown as Parameters<typeof fetchSpeciesObservationStats>[1];
}

class FakeQuery {
  private filters: Record<string, unknown> = {};
  private operation: "select" | "upsert" | "update" = "select";
  private payload: Record<string, unknown> | null = null;

  constructor(
    private table: string,
    private state: {
      speciesRows: Array<Record<string, unknown>>;
      cacheRows: Array<Record<string, unknown>>;
      upserts: Array<Record<string, unknown>>;
      updates: Array<Record<string, unknown>>;
    },
  ) {}

  select(): FakeQuery {
    this.operation = "select";
    return this;
  }

  limit(): FakeQuery {
    return this;
  }

  abortSignal(): Promise<unknown> {
    return this.execute();
  }

  eq(column: string, value: unknown): FakeQuery {
    this.filters[column] = value;
    return this;
  }

  upsert(payload: Record<string, unknown>): FakeQuery {
    this.operation = "upsert";
    this.payload = payload;
    return this;
  }

  update(payload: Record<string, unknown>): FakeQuery {
    this.operation = "update";
    this.payload = payload;
    return this;
  }

  then<TResult1 = unknown, TResult2 = never>(
    onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): PromiseLike<TResult1 | TResult2> {
    return this.execute().then(onfulfilled, onrejected);
  }

  private execute(): Promise<unknown> {
    if (this.operation === "upsert") {
      this.state.upserts.push(this.payload ?? {});
      return Promise.resolve({ data: null, error: null });
    }

    if (this.operation === "update") {
      this.state.updates.push({
        ...(this.payload ?? {}),
        filters: this.filters,
      });
      return Promise.resolve({ data: null, error: null });
    }

    const rows = this.table === "species_dictionary"
      ? this.state.speciesRows
      : this.state.cacheRows;
    return Promise.resolve({
      data: rows.filter((row) =>
        Object.entries(this.filters).every(([key, value]) => row[key] === value)
      ),
      error: null,
    });
  }
}
