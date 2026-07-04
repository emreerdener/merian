import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  insertScan,
  normalizeScanEcologyType,
  resolveScanGeoprivacy,
  speciesReferenceImageRowsFromCache,
} from "./db.ts";

Deno.test("speciesReferenceImageRowsFromCache splits, dedupes, and maps sources", () => {
  const rows = speciesReferenceImageRowsFromCache(
    "species-id",
    [
      "https://example.org/wiki-hero.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://static.inaturalist.org/photo-a.jpg",
      "https://upload.wikimedia.org/photo-b.jpg",
    ].join(", "),
    "https://en.wikipedia.org/wiki/Test_species",
  );

  assertEquals(
    rows.map((row) => ({
      species_id: row.species_id,
      url: row.url,
      source: row.source,
      sort_order: row.sort_order,
    })),
    [
      {
        species_id: "species-id",
        url: "https://example.org/wiki-hero.jpg",
        source: "wikipedia",
        sort_order: 0,
      },
      {
        species_id: "species-id",
        url: "https://static.inaturalist.org/photo-a.jpg",
        source: "gbif",
        sort_order: 1,
      },
      {
        species_id: "species-id",
        url: "https://upload.wikimedia.org/photo-b.jpg",
        source: "wikipedia",
        sort_order: 2,
      },
    ],
  );
});

Deno.test("speciesReferenceImageRowsFromCache returns no rows for sparse cache", () => {
  assertEquals(
    speciesReferenceImageRowsFromCache("species-id", " , ", null),
    [],
  );
});

function makeSupabaseMock(
  defaultGeoprivacy: unknown,
  error: { message: string } | null = null,
) {
  const calls: string[] = [];
  const query = {
    select(columns: string) {
      calls.push(`select:${columns}`);
      return this;
    },
    eq(column: string, value: string) {
      calls.push(`eq:${column}:${value}`);
      return this;
    },
    maybeSingle() {
      calls.push("maybeSingle");
      return Promise.resolve({
        data: defaultGeoprivacy === undefined
          ? null
          : { default_geoprivacy: defaultGeoprivacy },
        error,
      });
    },
  };

  return {
    calls,
    client: {
      from(table: string) {
        calls.push(`from:${table}`);
        return query;
      },
    } as unknown as SupabaseClient,
  };
}

Deno.test("resolveScanGeoprivacy preserves explicit valid values without a users query", async () => {
  const mock = makeSupabaseMock("open");

  const geoprivacy = await resolveScanGeoprivacy(
    "user-1",
    mock.client,
    "private",
  );

  assertEquals(geoprivacy, "private");
  assertEquals(mock.calls, []);
});

Deno.test("resolveScanGeoprivacy reads the user's default geoprivacy", async () => {
  const mock = makeSupabaseMock("obscured");

  const geoprivacy = await resolveScanGeoprivacy("user-1", mock.client);

  assertEquals(geoprivacy, "obscured");
  assertEquals(mock.calls, [
    "from:users",
    "select:default_geoprivacy",
    "eq:id:user-1",
    "maybeSingle",
  ]);
});

Deno.test("resolveScanGeoprivacy falls back to open for missing or invalid defaults", async () => {
  const missingMock = makeSupabaseMock(undefined);
  const invalidMock = makeSupabaseMock("friends-only");

  assertEquals(
    await resolveScanGeoprivacy("missing-user", missingMock.client),
    "open",
  );
  assertEquals(
    await resolveScanGeoprivacy("invalid-user", invalidMock.client),
    "open",
  );
});

Deno.test("resolveScanGeoprivacy throws when the default lookup fails", async () => {
  const mock = makeSupabaseMock(undefined, { message: "database unavailable" });

  await assertRejects(
    () => resolveScanGeoprivacy("user-1", mock.client),
    Error,
    "resolveScanGeoprivacy: database unavailable",
  );
});

Deno.test("normalizeScanEcologyType preserves valid scan ecology values", () => {
  assertEquals(normalizeScanEcologyType("wild"), "wild");
  assertEquals(normalizeScanEcologyType("urban"), "urban");
  assertEquals(normalizeScanEcologyType("domesticated"), "domesticated");
  assertEquals(normalizeScanEcologyType("unknown"), "unknown");
});

Deno.test("normalizeScanEcologyType clamps missing or invalid values to unknown", () => {
  assertEquals(normalizeScanEcologyType(undefined), "unknown");
  assertEquals(normalizeScanEcologyType(null), "unknown");
  assertEquals(normalizeScanEcologyType("terrestrial"), "unknown");
  assertEquals(normalizeScanEcologyType(""), "unknown");
});

Deno.test("insertScan clears public location labels for private scans", async () => {
  let upsertedRow: Record<string, unknown> | null = null;
  const mock = {
    from(table: string) {
      assertEquals(table, "scans");
      return {
        upsert(row: Record<string, unknown>) {
          upsertedRow = row;
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  await insertScan(
    {
      id: "scan-1",
      user_id: "user-1",
      species_id: null,
      geoprivacy: "private",
      is_biological_subject: true,
      extracted_visual_traits: [],
      colors: [],
      image_storage_urls: [],
      ecological_interactions: [],
      inference_tier: "free",
      public_location_label: "Austin, Texas",
      is_invasive: true,
      invasive_status_region: "Austin, TX",
      invasive_rationale:
        "Flagged from the original AI location-aware assessment.",
      invasive_confidence: 0.91,
    },
    mock,
  );

  if (upsertedRow === null) {
    throw new Error("Expected scans upsert row");
  }
  const row = upsertedRow as Record<string, unknown>;
  assertEquals(row.geoprivacy, "private");
  assertEquals(row.public_location_label, null);
  assertEquals(row.invasive_status_region, "Austin, TX");
  assertEquals(
    row.invasive_rationale,
    "Flagged from the original AI location-aware assessment.",
  );
  assertEquals(row.invasive_confidence, 0.91);
});

Deno.test("insertScan writes unknown ecology for non-biological scans without ecology_type", async () => {
  let upsertedRow: Record<string, unknown> | null = null;
  const mock = {
    from(table: string) {
      assertEquals(table, "scans");
      return {
        upsert(row: Record<string, unknown>) {
          upsertedRow = row;
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  await insertScan(
    {
      id: "scan-2",
      user_id: "user-1",
      species_id: null,
      geoprivacy: "open",
      is_biological_subject: false,
      extracted_visual_traits: ["self-illuminated screen"],
      colors: [],
      image_storage_urls: [
        "https://media.merian.app/public_uploads/pro/u/1.webp",
      ],
      ecological_interactions: [],
      inference_tier: "pro",
      ecology_type: null,
    },
    mock,
  );

  if (upsertedRow === null) {
    throw new Error("Expected scans upsert row");
  }
  const row = upsertedRow as Record<string, unknown>;
  assertEquals(row.ecology_type, "unknown");
});

Deno.test("insertScan preserves structured captured media manifest", async () => {
  let upsertedRow: Record<string, unknown> | null = null;
  const mock = {
    from(table: string) {
      assertEquals(table, "scans");
      return {
        upsert(row: Record<string, unknown>) {
          upsertedRow = row;
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;
  const capturedMedia = [
    {
      video: {
        _0: {
          video: {
            storage: "remoteURL",
            path: "https://media.merian.app/public_uploads/pro/u/clip.mp4",
          },
          thumbnail: {
            storage: "remoteURL",
            path: "https://media.merian.app/public_uploads/pro/u/frame.webp",
          },
        },
      },
    },
  ];

  await insertScan(
    {
      id: "scan-3",
      user_id: "user-1",
      species_id: null,
      geoprivacy: "open",
      is_biological_subject: false,
      extracted_visual_traits: ["moving screen"],
      colors: [],
      image_storage_urls: [
        "https://media.merian.app/public_uploads/pro/u/frame.webp",
      ],
      video_storage_urls: [
        "https://media.merian.app/public_uploads/pro/u/clip.mp4",
      ],
      captured_media: capturedMedia,
      ecological_interactions: [],
      inference_tier: "pro",
    },
    mock,
  );

  if (upsertedRow === null) {
    throw new Error("Expected scans upsert row");
  }
  const row = upsertedRow as Record<string, unknown>;
  assertEquals(row.captured_media, capturedMedia);
});
