import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
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
    { scientificName: "Danaus plexippus" },
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
}) {
  const state = {
    speciesRows: input.speciesRows,
    cacheRows: input.cacheRows,
    upserts: [] as Array<Record<string, unknown>>,
    updates: [] as Array<Record<string, unknown>>,
  };
  return {
    state,
    from(table: string) {
      return new FakeQuery(table, state);
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
