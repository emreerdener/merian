import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ContractValueError,
  merianModelContract,
  normalizePrimaryIdentification,
  parseIdentifySuccessEnvelope,
  parsePrimaryIdentification,
  PRIMARY_IDENTIFICATION_SCHEMA,
  type PrimaryIdentification,
  providerSchemaFromContract,
} from "./contract.ts";
import {
  buildCompletedIdentifyEnvelope,
  type CompletedScanResponseRow,
  fetchCompletedIdentifyResponse,
} from "./completedResponse.ts";

const provenance = {
  version: 2,
  provider: "openai",
  binding: "openai_photo_v1",
  model: "gpt-6-sol",
  variant: "multimodal",
  operation: "scan_identification",
  policy_version: 2,
  prompt: "synthetic_primary_fixture_v1",
  schema: PRIMARY_IDENTIFICATION_SCHEMA,
  confidence: "openai_unqualified_v1",
  diagnostic_trigger: null,
  prompt_diagnostic_trigger: null,
  safety: "openai_photo_moderation_v1",
  timeout_ms: 90000,
  generation: {
    max_output_tokens: 8192,
    reasoning_effort: "low",
    image_detail: "high",
  },
};
const states: PrimaryIdentification[] = [
  {
    version: 1,
    resolution: "species",
    scientific_name: "Examplea prima",
    common_name: "Synthetic species",
  },
  {
    version: 1,
    resolution: "genus",
    scientific_name: "Examplea",
    common_name: "Synthetic genus",
  },
  {
    version: 1,
    resolution: "family",
    scientific_name: "Exampleaceae",
    common_name: "Synthetic family",
  },
  {
    version: 1,
    resolution: "unresolved_biological",
    scientific_name: null,
    common_name: null,
  },
  {
    version: 1,
    resolution: "non_biological",
    scientific_name: null,
    common_name: "Synthetic object",
  },
];
function scan(primary: PrimaryIdentification): CompletedScanResponseRow {
  return {
    id: "00000000-0000-4000-8000-000000000111",
    user_id: "00000000-0000-4000-8000-000000000222",
    species_id: null,
    device_locale: null,
    ai_confidence_score: 0.75,
    is_biological_subject: primary.resolution !== "non_biological",
    is_live_capture: true,
    blur_score: 0,
    ecology_type: null,
    is_invasive: null,
    invasive_status_region: null,
    invasive_rationale: null,
    invasive_confidence: null,
    colors: [],
    estimated_size_cm: null,
    life_stage: null,
    reproductive_condition: null,
    sex: null,
    sex_confidence: null,
    sex_evidence: null,
    individual_count: null,
    ecological_interactions: null,
    ai_reasoning: "Synthetic fixture explanation.",
    extracted_visual_traits: ["synthetic feature"],
    inference_tier: "flash",
    identification_provenance: provenance,
    primary_identification: primary,
    candidates: null,
    image_quality_score: 80,
    pet_identification: null,
  };
}
function envelope(primary = states[0]) {
  return buildCompletedIdentifyEnvelope(scan(primary), null);
}

Deno.test("primary snapshot has five explicit states and strict nullable name bounds", () => {
  for (const state of states) {
    assertEquals(parsePrimaryIdentification(state), state);
    assert(Object.isFrozen(parsePrimaryIdentification(state)));
  }
  const base = states[0];
  for (
    const invalid of [
      null,
      [],
      {},
      { ...base, extra: true },
      { ...base, version: 2 },
      { ...base, version: "1" },
      { ...base, resolution: "subspecies" },
      { ...base, scientific_name: undefined },
      { ...base, scientific_name: null },
      { ...base, common_name: undefined },
      { ...base, common_name: "" },
      { ...base, common_name: " synthetic" },
      { ...base, common_name: "synthetic\u00a0" },
      { ...base, common_name: "syn\n thetic" },
      { ...base, common_name: "syn\u007fthetic" },
      { ...base, common_name: "x".repeat(256) },
      { ...base, common_name: "🦋".repeat(128) },
      { ...states[3], scientific_name: "Examplea" },
    ]
  ) assertThrows(() => parsePrimaryIdentification(invalid), ContractValueError);
  assertEquals(
    parsePrimaryIdentification({ ...base, common_name: "🦋".repeat(127) })
      .common_name?.length,
    254,
  );
});

Deno.test("normalization retains declared rank without deriving it from names or model score", () => {
  const primary = normalizePrimaryIdentification("genus", {
    scientific_name: "  Synthetic two-word label ",
    common_name: " ",
    is_biological_subject: true,
  });
  assertEquals(primary, {
    version: 1,
    resolution: "genus",
    scientific_name: "Synthetic two-word label",
    common_name: null,
  });
  assertThrows(() =>
    normalizePrimaryIdentification("non_biological", {
      scientific_name: null,
      common_name: null,
      is_biological_subject: true,
    }), ContractValueError);
  assertEquals(
    providerSchemaFromContract(merianModelContract).properties
      ?.primary_identification,
    undefined,
  );
});

Deno.test("wire binds primary identity to its schema, projected names and biological flag", () => {
  for (const state of states) {
    const result = envelope(state);
    assertEquals(
      parseIdentifySuccessEnvelope(JSON.parse(JSON.stringify(result))),
      result,
    );
    assertEquals(result.data.scientific_name, state.scientific_name);
    assertEquals(result.data.common_name, state.common_name);
    for (
      const changes of [
        { primary_identification: undefined },
        { primary_identification: null },
        { identification_provenance: undefined },
        {
          identification_provenance: {
            ...provenance,
            schema: "merian_openai_identify_v1",
          },
        },
        { scientific_name: "Contradictory label" },
        { common_name: undefined },
        { is_biological_subject: !result.data.is_biological_subject },
      ]
    ) {
      assertThrows(() =>
        parseIdentifySuccessEnvelope({
          success: true,
          data: { ...result.data, ...changes },
        }), ContractValueError);
    }
  }
});

Deno.test("non-species results cannot carry species effects or a narrower family lineage", () => {
  for (const state of states.slice(1)) {
    const result = envelope(state);
    for (
      const change of [
        { candidates: [] },
        { is_new_to_merian_dictionary: true },
        { reference_image_url: "https://example.invalid/species.jpg" },
        { wikipedia_url: "https://example.invalid/species" },
        { wikipedia_overview: "Species content" },
        { species_insights: { habitat_description: "Species content" } },
        { gbif_taxon_key: 1 },
        { iucn_red_list_status: "least_concern" },
        { alternative_common_names: [] },
      ]
    ) {
      assertThrows(() =>
        parseIdentifySuccessEnvelope({
          success: true,
          data: { ...result.data, ...change },
        }), ContractValueError);
    }
  }
  assertThrows(() =>
    parseIdentifySuccessEnvelope({
      success: true,
      data: {
        ...envelope(states[2]).data,
        taxonomy: { family: "Exampleaceae", genus: "Examplea" },
      },
    }), ContractValueError);
});

Deno.test("explicit species alternatives require their own species rank and are bounded", () => {
  const result = envelope();
  const candidate = {
    scientific_name: "Examplea altera",
    confidence_score: 0.1,
    distinguishing_feature: "Synthetic difference",
    taxon_rank: "species" as const,
  };
  for (const candidates of [null, [], [candidate], [candidate, candidate]]) {
    assertEquals(
      parseIdentifySuccessEnvelope({
        success: true,
        data: { ...result.data, candidates },
      }).data.candidates,
      candidates,
    );
  }
  for (
    const candidates of [[{ ...candidate, taxon_rank: undefined }], [{
      ...candidate,
      taxon_rank: "genus",
    }], [candidate, candidate, candidate]]
  ) {
    assertThrows(
      () =>
        parseIdentifySuccessEnvelope({
          success: true,
          data: { ...result.data, candidates },
        }),
      ContractValueError,
    );
  }
  assertThrows(() =>
    parseIdentifySuccessEnvelope({
      success: true,
      data: {
        ...result.data,
        primary_identification: undefined,
        identification_provenance: undefined,
        candidates: [candidate],
      },
    }), ContractValueError);
});

function database(
  row: CompletedScanResponseRow,
  stored: unknown,
  backup: Pick<
    CompletedScanResponseRow,
    "identification_provenance" | "primary_identification"
  > = row,
  status = "complete",
  delayedBackup = false,
) {
  const tables: string[] = [];
  const client = {
    from(table: string) {
      tables.push(table);
      const query = {
        select: () => query,
        abortSignal: () => query,
        eq: (key: string, value: unknown) => {
          assertEquals(value, key === "user_id" ? row.user_id : row.id);
          return query;
        },
        maybeSingle: () => {
          assert(
            table !== "species_dictionary",
            "Recovery cannot query a species without an association",
          );
          const visibleBackup = delayedBackup && tables.length === 1
            ? {}
            : backup;
          return Promise.resolve({
            data: table === "scans" ? row : {
              status,
              response_envelope: stored,
              identification_provenance:
                visibleBackup.identification_provenance,
              primary_identification: visibleBackup.primary_identification,
            },
            error: null,
          });
        },
      };
      return query;
    },
  } as unknown as SupabaseClient;
  return { client, tables };
}

Deno.test("stored, reconstructed and unfinished owner replay retain every primary state without a species query", async () => {
  for (const state of states) {
    const row = scan(state);
    const expected = envelope(state);
    for (const source of ["stored", "reconstructed"] as const) {
      const db = database(row, source === "stored" ? expected : null);
      const result = await fetchCompletedIdentifyResponse(
        row.id,
        row.user_id,
        db.client,
      );
      assertEquals(result, { source, envelope: expected });
      assertEquals(db.tables.includes("species_dictionary"), false);
    }
    const pending = database(row, null, { ...row }, "finalizing");
    assertEquals(
      (await fetchCompletedIdentifyResponse(
        row.id,
        row.user_id,
        pending.client,
      ))?.envelope.data.primary_identification,
      state,
    );
  }
});

Deno.test("damaged or downgraded stored envelope reconstructs only from the matching durable generation", async () => {
  const row = scan(states[1]);
  const expected = envelope(states[1]);
  const changed = envelope({ ...states[1], common_name: "Changed label" });
  const legacy = buildCompletedIdentifyEnvelope({
    ...row,
    primary_identification: null,
    identification_provenance: null,
  }, null);
  for (
    const stored of [changed, legacy, {
      ...expected,
      data: { ...expected.data, primary_identification: null },
    }]
  ) {
    const db = database(row, stored);
    assertEquals(
      await fetchCompletedIdentifyResponse(row.id, row.user_id, db.client),
      { source: "reconstructed", envelope: expected },
    );
  }
  for (
    const corrupt of [
      { ...row, primary_identification: null },
      { ...row, primary_identification: null, identification_provenance: null },
      {
        ...row,
        primary_identification: { ...states[1], common_name: "Changed label" },
      },
      {
        ...row,
        identification_provenance: { ...provenance, policy_version: 3 },
      },
      { ...row, species_id: "00000000-0000-4000-8000-000000000333" },
    ]
  ) {
    const db = database(corrupt, legacy, { ...row });
    await assertRejects(
      () => fetchCompletedIdentifyResponse(row.id, row.user_id, db.client),
      Error,
      "primary_identification_replay_integrity",
    );
    assertEquals(db.tables.includes("species_dictionary"), false);
  }
});

Deno.test("reconstruction never launders contradictory biological flags, alternatives or pet data", () => {
  const row = scan(states[1]);
  for (
    const bad of [
      { ...row, is_biological_subject: false },
      { ...row, candidates: [] },
      { ...row, pet_identification: { label: "Synthetic pet" } },
      { ...row, primary_identification: { ...states[1], version: 2 } },
    ]
  ) assertThrows(() => buildCompletedIdentifyEnvelope(bad, null));
  const candidate = {
    scientific_name: "Examplea altera",
    confidence_score: 0.2,
    distinguishing_feature: "Synthetic difference",
    taxon_rank: "species" as const,
  };
  const speciesRow = { ...scan(states[0]), candidates: [candidate] };
  assertEquals(
    buildCompletedIdentifyEnvelope(speciesRow, null).data.candidates,
    [candidate],
  );
  assertThrows(() =>
    buildCompletedIdentifyEnvelope({
      ...speciesRow,
      candidates: [{ ...candidate, taxon_rank: undefined }],
    }, null)
  );
});

Deno.test("concurrent owner insertion refreshes a stale empty job backup before replay comparison", async () => {
  const row = scan(states[1]);
  const db = database(row, null, row, "finalizing", true);
  assertEquals(
    await fetchCompletedIdentifyResponse(row.id, row.user_id, db.client),
    {
      source: "reconstructed",
      envelope: envelope(states[1]),
    },
  );
  assertEquals(db.tables, [
    "scan_ingestion_jobs",
    "scans",
    "scan_ingestion_jobs",
  ]);
  const damaged = database(row, null, {}, "finalizing", true);
  await assertRejects(
    () => fetchCompletedIdentifyResponse(row.id, row.user_id, damaged.client),
    Error,
    "primary_identification_replay_integrity",
  );
});
