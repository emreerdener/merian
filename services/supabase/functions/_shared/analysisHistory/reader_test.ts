import { assertEquals, assertThrows } from "@std/assert";
import { HistoryError, type HistoryPageRequest } from "./contract.ts";
import { parseHistoryPage } from "./page.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";

const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const request: HistoryPageRequest = {
  schema_version: 1,
  observation_id: fixture.observation_id,
  before_ordinal: null,
  limit: 20,
};

Deno.test("history reader preserves original wire bytes and binds Identify to observation, not analysis", () => {
  const page = parseHistoryPage(fixture, request, fixture.owner_id);
  assertEquals(page.items[0].snapshot, fixture.items[0].snapshot);
  const snapshot = decodeAnalysisResultSnapshot(page.items[0].snapshot);
  assertEquals(snapshot.result.scan_id, fixture.observation_id);
  assertEquals(snapshot.ordinal, 1);
  assertEquals(
    snapshot.evidence_manifest.schema_version === 1
      ? snapshot.evidence_manifest.captured_media.length
      : 0,
    1,
  );
});

Deno.test("history reader rejects forged identities, cursors and duplicate IDs without partial acceptance", () => {
  for (
    const patch of [
      { owner_id: request.observation_id },
      { observation_id: fixture.owner_id },
      { schema_version: 2 },
      { state_revision: true },
      { next_before_ordinal: 0 },
      { next_before_ordinal: 2 },
      { items: [...fixture.items, ...fixture.items] },
      { extra: true },
      { items: Array(21).fill(fixture.items[0]) },
    ]
  ) {
    assertThrows(
      () =>
        parseHistoryPage({ ...fixture, ...patch }, request, fixture.owner_id),
      HistoryError,
    );
  }
  assertThrows(
    () =>
      parseHistoryPage(
        fixture,
        { ...request, before_ordinal: 1 },
        fixture.owner_id,
      ),
    HistoryError,
  );
});

Deno.test("history page preserves server projection metadata outside the Identify validation view", () => {
  const raw = JSON.parse(fixture.items[0].snapshot);
  raw.result.species_id = "00000000-0000-4000-8000-000000000004";
  const snapshot = JSON.stringify(raw);
  const page = parseHistoryPage(
    {
      ...fixture,
      items: [{ ordinal: raw.ordinal, snapshot }],
    },
    request,
    fixture.owner_id,
  );
  assertEquals(page.items[0].snapshot, snapshot);
  assertEquals(
    JSON.parse(page.items[0].snapshot).result.species_id,
    raw.result.species_id,
  );
  assertEquals(
    Object.hasOwn(decodeAnalysisResultSnapshot(snapshot).result, "species_id"),
    false,
  );
});

Deno.test("immutable result rejects incomplete or mixed evidence and oversized bytes", () => {
  const base = JSON.parse(fixture.items[0].snapshot);
  for (
    const patch of [
      { schema_version: 2 },
      { ordinal: 0 },
      { source_analysis_id: base.analysis_id },
      { completed_at_ms: -1 },
      { completed_at_ms: 1.5 },
      { request_digest: "bad" },
      { result: {} },
      { result: { ...base.result, scan_id: base.analysis_id } },
      { evidence_manifest: { schema_version: 1, captured_media: [] } },
      {
        evidence_manifest: {
          schema_version: 1,
          captured_media: [{
            image: { _0: { storage: "localFile", path: "fixture.jpg" } },
          }],
        },
      },
      {
        evidence_manifest: {
          schema_version: 2,
          captured_media: base.evidence_manifest.captured_media,
        },
      },
      { review: {} },
    ]
  ) {
    assertThrows(
      () => decodeAnalysisResultSnapshot(JSON.stringify({ ...base, ...patch })),
      HistoryError,
    );
  }
  assertThrows(
    () =>
      decodeAnalysisResultSnapshot(
        fixture.items[0].snapshot + " ".repeat(1_048_576),
      ),
    HistoryError,
  );
  const mixed = structuredClone(fixture);
  mixed.items[0].ordinal = 2;
  assertThrows(
    () => parseHistoryPage(mixed, request, fixture.owner_id),
    HistoryError,
  );
});

Deno.test("keyset paging accepts a descending prefix even when completion times tie", () => {
  const base = JSON.parse(fixture.items[0].snapshot);
  const items = [3, 2].map((ordinal) => ({
    ordinal,
    snapshot: JSON.stringify({
      ...base,
      ordinal,
      analysis_id: `00000000-0000-4000-8000-00000000001${ordinal}`,
    }),
  }));
  const page = parseHistoryPage({ ...fixture, items, next_before_ordinal: 2 }, {
    ...request,
    before_ordinal: 4,
    limit: 2,
  }, fixture.owner_id);
  assertEquals(page.next_before_ordinal, 2);
  assertEquals(page.items.length, 2);
});

Deno.test("protocol 8 accepts mixed exact V1/V2 snapshots while protocol 7 refuses V2", async () => {
  const mixed = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/page-v2.json", import.meta.url),
    ),
  );
  assertThrows(
    () => parseHistoryPage(mixed, request, mixed.owner_id),
    HistoryError,
  );
  assertEquals(
    parseHistoryPage(mixed, request, mixed.owner_id, 8).items,
    mixed.items,
  );
  const original = JSON.parse(mixed.items[0].snapshot);
  for (
    const patch of [
      { schema_version: 3 },
      { schema_version: 1 },
      {
        evidence_manifest: {
          ...original.evidence_manifest,
          url: "https://example.invalid",
        },
      },
      {
        evidence_manifest: {
          schema_version: 2,
          items: [{
            ...original.evidence_manifest.items[0],
            media_id: original.analysis_id,
          }],
        },
      },
      {
        evidence_manifest: {
          schema_version: 2,
          items: [
            original.evidence_manifest.items[0],
            original.evidence_manifest.items[0],
          ],
        },
      },
    ]
  ) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({ ...original, ...patch }),
        8,
      ), HistoryError);
  }
});

Deno.test("protocol9 imports preserve unknown execution facts and reject older readers", () => {
  const result = {
    scan_id: fixture.observation_id,
    primary_identification: null,
    identification_provenance: null,
    species_id: null,
    is_biological_subject: true,
    candidates: {},
    pet_identification: null,
    ai_confidence_score: 0.75,
    ai_reasoning: "Synthetic surviving saved identification.",
    inference_tier: "flash",
  };
  const imported = {
    schema_version: 3,
    observation_id: fixture.observation_id,
    analysis_id: "00000000-0000-4000-8000-000000000002",
    source_analysis_id: null,
    request_digest: null,
    completed_at_ms: null,
    ordinal: 1,
    result,
    evidence_manifest: {
      schema_version: 3,
      origin: "saved_identification",
      imported_at_ms: 1_750_000_000_000,
      availability: "unavailable",
    },
  };
  const primaryProvenance = {
    "version": 2,
    "provider": "openai",
    "binding": "openai_photo_v1",
    "model": "gpt-6-sol",
    "variant": "multimodal",
    "operation": "scan_identification",
    "policy_version": 2,
    "prompt": "synthetic_primary_fixture_v1",
    "schema": "merian_identify_primary_v1",
    "confidence": "openai_unqualified_v1",
    "diagnostic_trigger": null,
    "prompt_diagnostic_trigger": null,
    "safety": "openai_photo_moderation_v1",
    "timeout_ms": 90000,
    "generation": {
      "max_output_tokens": 8192,
      "reasoning_effort": "low",
      "image_detail": "high",
    },
  };
  const bytes = JSON.stringify(imported);
  const page = { ...fixture, items: [{ ordinal: 1, snapshot: bytes }] };
  assertEquals(
    parseHistoryPage(page, request, fixture.owner_id, 9).items[0].snapshot,
    bytes,
  );
  assertEquals(decodeAnalysisResultSnapshot(bytes, 9).completed_at_ms, null);
  for (const reader of [7, 8] as const) {
    assertThrows(
      () => parseHistoryPage(page, request, fixture.owner_id, reader),
      HistoryError,
    );
  }
  for (
    const patch of [
      { source_analysis_id: fixture.observation_id },
      { request_digest: "a".repeat(64) },
      { completed_at_ms: 1_750_000_000_000 },
      { ordinal: 2 },
      { result: { ...result, user_confirmed_identification: true } },
      { result: { ...result, ai_confidence_score: null } },
      { result: { ...result, primary_identification: {} } },
      { result: { ...result, identification_provenance: primaryProvenance } },
      {
        result: {
          ...result,
          primary_identification: {
            version: 1,
            resolution: "genus",
            scientific_name: "Savedfixture",
            common_name: null,
          },
        },
      },

      {
        evidence_manifest: {
          ...imported.evidence_manifest,
          availability: "available",
        },
      },
      {
        evidence_manifest: {
          ...imported.evidence_manifest,
          origin: "original",
        },
      },
      {
        evidence_manifest: {
          ...imported.evidence_manifest,
          imported_at_ms: null,
        },
      },
      {
        evidence_manifest: {
          ...imported.evidence_manifest,
          imported_at_ms: 1.5,
        },
      },
      {
        evidence_manifest: {
          ...imported.evidence_manifest,
          url: "https://example.invalid",
        },
      },
    ]
  ) {
    assertThrows(
      () =>
        decodeAnalysisResultSnapshot(
          JSON.stringify({ ...imported, ...patch }),
          9,
        ),
      HistoryError,
    );
  }
  assertEquals(
    parseHistoryPage(fixture, request, fixture.owner_id, 9).items,
    fixture.items,
  );
});

Deno.test("saved baseline acknowledgement cannot supply current selection or another account", async () => {
  const { parseSavedHistoryEnrollment } = await import(
    "./savedIdentification.ts"
  );
  const receipt = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/enrollment-v1.json", import.meta.url),
    ),
  );
  assertEquals(
    parseSavedHistoryEnrollment(
      receipt,
      fixture.owner_id,
      fixture.observation_id,
    ),
    receipt,
  );
  for (
    const patch of [
      { owner_id: fixture.observation_id },
      { baseline_analysis_id: fixture.observation_id },
      { baseline_analysis_id: fixture.owner_id },
      { selected_analysis_id: receipt.baseline_analysis_id },
      { observation_revision: 1 },
    ]
  ) {
    assertThrows(
      () =>
        parseSavedHistoryEnrollment(
          { ...receipt, ...patch },
          fixture.owner_id,
          fixture.observation_id,
        ),
      HistoryError,
    );
  }
});

Deno.test("shared native V3 fixture has no original completion or private media proof", async () => {
  const imported = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/page-v3.json", import.meta.url),
    ),
  );
  assertEquals(
    parseHistoryPage(imported, request, imported.owner_id, 9).items,
    imported.items,
  );
  assertThrows(
    () => parseHistoryPage(imported, request, imported.owner_id, 8),
    HistoryError,
  );
});
