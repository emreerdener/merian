import {
  assertEquals,
  assertExists,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildCompletedIdentifyEnvelope,
  type CompletedScanResponseRow,
  type CompletedSpeciesResponseRow,
  fetchCompletedIdentifyResponse,
} from "./completedResponse.ts";

const scan: CompletedScanResponseRow = {
  id: "00000000-0000-4000-8000-000000000101",
  user_id: "00000000-0000-4000-8000-000000000201",
  species_id: "00000000-0000-4000-8000-000000000301",
  device_locale: "tr-TR",
  ai_confidence_score: 0.94,
  is_biological_subject: true,
  is_live_capture: true,
  blur_score: 0.1,
  ecology_type: "wild",
  is_invasive: false,
  invasive_status_region: "Texas",
  invasive_rationale: "Native range overlaps the observation.",
  invasive_confidence: 0.9,
  colors: ["blue", "gray"],
  estimated_size_cm: 110,
  life_stage: "adult",
  reproductive_condition: "nesting",
  sex: "cannot_determine",
  sex_confidence: null,
  sex_evidence: null,
  individual_count: 1,
  ecological_interactions: ["standing in shallow water"],
  ai_reasoning: "Large wading bird with a long yellow bill.",
  extracted_visual_traits: ["black cap", "gray-blue wings"],
  inference_tier: "pro",
  candidates: null,
  image_quality_score: 87,
  pet_identification: null,
};

const species: CompletedSpeciesResponseRow = {
  id: "00000000-0000-4000-8000-000000000301",
  scientific_name: "Ardea herodias",
  common_names: {
    en: "Great Blue Heron",
    tr: "Büyük mavi balıkçıl",
  },
  alternative_common_names: ["Great Blue/cocoi Heron"],
  kingdom: "Animalia",
  phylum: "Chordata",
  class: "Aves",
  order: "Pelecaniformes",
  family: "Ardeidae",
  genus: "Ardea",
  hazard_type: "none",
  wikipedia_url: "https://en.wikipedia.org/wiki/Great_blue_heron",
  wikipedia_overview: "A large wading bird.",
  reference_image_url: "https://example.com/heron.jpg",
  iucn_red_list_status: "least_concern",
  habitat_description: "Wetlands and shorelines.",
  gbif_taxon_key: 2480498,
  group_tags: ["birds"],
};

Deno.test("completed Identify response reconstruction satisfies the wire contract", () => {
  const envelope = buildCompletedIdentifyEnvelope(scan, species);

  assertEquals(envelope.success, true);
  assertEquals(envelope.data.scan_id, scan.id);
  assertEquals(envelope.data.scientific_name, "Ardea herodias");
  assertEquals(envelope.data.common_name, "Büyük mavi balıkçıl");
  assertEquals(envelope.data.confidence_score, 0.94);
  assertEquals(envelope.data.inference_tier, "pro");
  assertEquals(envelope.data.image_quality.overall_score, 87);
  assertExists(envelope.data.taxonomy);
});

Deno.test("completed Identify response reconstruction is safe for sparse legacy rows", () => {
  const envelope = buildCompletedIdentifyEnvelope(
    {
      ...scan,
      species_id: null,
      device_locale: null,
      ai_confidence_score: null,
      blur_score: null,
      colors: null,
      estimated_size_cm: null,
      inference_tier: null,
      image_quality_score: null,
      ai_reasoning: null,
      extracted_visual_traits: null,
    },
    null,
  );

  assertEquals(envelope.data.scan_id, scan.id);
  assertEquals(envelope.data.confidence_score, 0);
  assertEquals(envelope.data.blur_score, 0);
  assertEquals(envelope.data.colors, []);
  assertEquals(envelope.data.estimated_size_cm, null);
  assertEquals(envelope.data.inference_tier, "flash");
  assertEquals(envelope.data.image_quality.overall_score, 0);
});

Deno.test("completed Identify reconstruction bounds malformed historical summaries", () => {
  const envelope = buildCompletedIdentifyEnvelope(
    {
      ...scan,
      ecology_type: "historical-invalid-value",
      invasive_status_region: "r".repeat(500),
      invasive_rationale: "i".repeat(900),
      invasive_confidence: 7,
      colors: Array.from(
        { length: 30 },
        (_, index) => `${index}-${"c".repeat(300)}`,
      ),
      life_stage: "historical-invalid-value",
      reproductive_condition: "historical-invalid-value",
      sex: "historical-invalid-value",
      sex_confidence: -4,
      sex_evidence: "e".repeat(900),
      ecological_interactions: Array.from(
        { length: 20 },
        () => "interaction".repeat(100),
      ),
      ai_reasoning: "a".repeat(4_000),
      extracted_visual_traits: Array.from(
        { length: 20 },
        (_, index) => `${index}-${"trait".repeat(200)}`,
      ),
      candidates: [
        { confidence_score: 0.9 },
        {
          scientific_name: "Legacy candidate without a saved distinction",
          confidence_score: 0.4,
        },
        {
          scientific_name: "s".repeat(500),
          confidence_score: 5,
          distinguishing_feature: "d".repeat(900),
          common_name: "n".repeat(500),
        },
      ],
      pet_identification: {
        species_group: "bird",
        label: "Invalid historical pet",
      },
    },
    {
      ...species,
      kingdom: "k".repeat(500),
      hazard_type: "historical-invalid-value",
      wikipedia_url: "u".repeat(5_000),
      wikipedia_overview: "w".repeat(25_000),
      habitat_description: "h".repeat(15_000),
      alternative_common_names: Array.from(
        { length: 120 },
        () => "alternative".repeat(40),
      ),
    },
  );

  assertEquals(envelope.data.ecology_type, undefined);
  assertEquals(envelope.data.invasive_status_region?.length, 160);
  assertEquals(envelope.data.invasive_rationale?.length, 500);
  assertEquals(envelope.data.invasive_confidence, 1);
  assertEquals(envelope.data.colors.length, 20);
  assertEquals(envelope.data.colors[0].length, 160);
  assertEquals(envelope.data.life_stage, undefined);
  assertEquals(envelope.data.reproductive_condition, undefined);
  assertEquals(envelope.data.sex, undefined);
  assertEquals(envelope.data.ai_reasoning.length, 2_000);
  assertEquals(envelope.data.extracted_visual_traits.length, 10);
  assertEquals(envelope.data.candidates?.length, 2);
  assertEquals(
    envelope.data.candidates?.[0].distinguishing_feature,
    "Saved alternative identification.",
  );
  assertEquals(envelope.data.candidates?.[1].scientific_name.length, 255);
  assertEquals(envelope.data.pet_identification, null);
  assertEquals(envelope.data.insight_data?.hazard_type, "none");
  assertEquals(envelope.data.wikipedia_url?.length, 4_096);
  assertEquals(envelope.data.wikipedia_overview?.length, 20_000);
  assertEquals(
    envelope.data.species_insights?.habitat_description?.length,
    10_000,
  );
  assertEquals(envelope.data.alternative_common_names?.length, 1);
  assertEquals(envelope.data.alternative_common_names?.[0].length, 255);
});

Deno.test("completed Identify lookup replays the immutable canonical owner response", async () => {
  const envelope = buildCompletedIdentifyEnvelope(scan, species);
  const observedFilters: Array<[string, string, unknown]> = [];
  const observedTables: string[] = [];
  const client = {
    from(table: string) {
      observedTables.push(table);
      return {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          observedFilters.push([table, column, value]);
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: table === "scan_ingestion_jobs"
              ? { status: "complete", response_envelope: envelope }
              : null,
            error: null,
          });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay?.source, "stored");
  assertEquals(replay?.envelope, envelope);
  assertEquals(observedTables, [
    "scan_ingestion_jobs",
    "scan_ingestion_jobs",
  ]);
  assertEquals(observedFilters, [
    ["scan_ingestion_jobs", "scan_id", scan.id],
    ["scan_ingestion_jobs", "user_id", scan.user_id],
    ["scan_ingestion_jobs", "scan_id", scan.id],
    ["scan_ingestion_jobs", "user_id", scan.user_id],
  ]);
});

Deno.test("non-complete Identify jobs do not replay without an exact durable scan", async () => {
  const observedTables: string[] = [];
  const client = {
    from(table: string) {
      observedTables.push(table);
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: table === "scan_ingestion_jobs"
              ? { status: "finalizing", response_envelope: null }
              : null,
            error: null,
          });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay, null);
  assertEquals(observedTables, ["scan_ingestion_jobs", "scans"]);
});

Deno.test("non-complete Identify jobs reconstruct an exact durable moderated scan", async () => {
  const observedTables: string[] = [];
  const client = {
    from(table: string) {
      observedTables.push(table);
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          if (table === "scan_ingestion_jobs") {
            return Promise.resolve({
              data: { status: "finalizing" },
              error: null,
            });
          }
          if (table === "scans") {
            return Promise.resolve({ data: scan, error: null });
          }
          return Promise.resolve({ data: species, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay?.source, "reconstructed");
  assertEquals(replay?.envelope.data.scan_id, scan.id);
  assertEquals(observedTables, [
    "scan_ingestion_jobs",
    "scans",
    "species_dictionary",
  ]);
});

Deno.test("stranded inline completion is repaired before owner-row reconstruction", async () => {
  let jobQueryCount = 0;
  const observedRpcCalls: Array<[string, Record<string, unknown>]> = [];
  const client = {
    rpc(name: string, parameters: Record<string, unknown>) {
      observedRpcCalls.push([name, parameters]);
      return Promise.resolve({ data: "completed", error: null });
    },
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          if (table === "scan_ingestion_jobs") {
            jobQueryCount += 1;
            return Promise.resolve(
              jobQueryCount === 1
                ? { data: { status: "failed_retryable" }, error: null }
                : { data: { response_envelope: null }, error: null },
            );
          }
          if (table === "scans") {
            return Promise.resolve({ data: scan, error: null });
          }
          return Promise.resolve({ data: species, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay?.source, "reconstructed");
  assertEquals(replay?.envelope.data.scan_id, scan.id);
  assertEquals(observedRpcCalls, [[
    "recover_inline_scan_ingestion_completion",
    {
      p_scan_id: scan.id,
      p_user_id: scan.user_id,
    },
  ]]);
});

Deno.test("missing inline recovery routine is safe during migration-first rollout", async () => {
  const client = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "PGRST202",
          message: "routine is not visible in the schema cache",
        },
      });
    },
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: table === "scan_ingestion_jobs"
              ? { status: "failed_retryable" }
              : null,
            error: null,
          });
        },
      };
    },
  } as unknown as SupabaseClient;

  assertEquals(
    await fetchCompletedIdentifyResponse(scan.id, scan.user_id, client),
    null,
  );
});

Deno.test("unexpected inline recovery errors fail visibly", async () => {
  const client = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "55000",
          message: "canonical_scan_media_incomplete",
        },
      });
    },
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: { status: "failed_retryable" },
            error: null,
          });
        },
      };
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () => fetchCompletedIdentifyResponse(scan.id, scan.user_id, client),
    Error,
    "canonical_scan_media_incomplete",
  );
});

Deno.test("an unrelated undefined function inside recovery is not treated as rollout propagation", async () => {
  const client = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: {
          code: "42883",
          message: "function internal.repair_media(uuid) does not exist",
        },
      });
    },
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          return Promise.resolve({
            data: { status: "failed_retryable" },
            error: null,
          });
        },
      };
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () => fetchCompletedIdentifyResponse(scan.id, scan.user_id, client),
    Error,
    "repair_media",
  );
});

Deno.test("completed Identify lookup reconstructs malformed legacy storage from the exact owner row", async () => {
  const observedFilters: Array<[string, string, unknown]> = [];
  const client = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq(column: string, value: unknown) {
          observedFilters.push([table, column, value]);
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          if (table === "scan_ingestion_jobs") {
            return Promise.resolve({
              data: {
                status: "complete",
                response_envelope: { success: true, data: {} },
              },
              error: null,
            });
          }
          if (table === "scans") {
            return Promise.resolve({ data: scan, error: null });
          }
          return Promise.resolve({ data: species, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay?.source, "reconstructed");
  assertEquals(replay?.envelope.data.scan_id, scan.id);
  assertEquals(
    observedFilters.some(([table, column, value]) =>
      table === "scans" &&
      column === "user_id" &&
      value === scan.user_id
    ),
    true,
  );
});

Deno.test("completed Identify lookup reconstructs when optional response storage is unavailable", async () => {
  let jobQueryCount = 0;
  const client = {
    from(table: string) {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        abortSignal() {
          return this;
        },
        maybeSingle() {
          if (table === "scan_ingestion_jobs") {
            jobQueryCount += 1;
            return Promise.resolve(
              jobQueryCount === 1
                ? { data: { status: "complete" }, error: null }
                : {
                  data: null,
                  error: {
                    code: "42703",
                    message: "column response_envelope does not exist",
                  },
                },
            );
          }
          if (table === "scans") {
            return Promise.resolve({ data: scan, error: null });
          }
          return Promise.resolve({ data: species, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const replay = await fetchCompletedIdentifyResponse(
    scan.id,
    scan.user_id,
    client,
  );

  assertEquals(replay?.source, "reconstructed");
  assertEquals(replay?.envelope.data.scan_id, scan.id);
});
