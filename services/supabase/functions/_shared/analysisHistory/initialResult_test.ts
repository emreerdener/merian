import { assertEquals, assertThrows } from "@std/assert";
import page from "./fixtures/page-v8.json" with { type: "json" };
import originals from "./fixtures/page-v8-originals.json" with { type: "json" };
import geometry from "./fixtures/page-v8-geometry.json" with { type: "json" };
import { decodeAnalysisResultSnapshot } from "./result.ts";
import { parseHistoryPage } from "./page.ts";
import { parseHistoryState } from "./state.ts";
import state from "./fixtures/state-v1.json" with { type: "json" };

const original = JSON.parse(page.items[0].snapshot);
Deno.test("reader18 requires exact V9 geometry proof and preserves historical versions", () => {
  assertEquals(
    decodeAnalysisResultSnapshot(geometry.items[0].snapshot, 18)
      .evidence_manifest.schema_version,
    9,
  );
  for (const reader of [7, 8, 9, 10, 11, 13, 14, 15, 16, 17] as const) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(geometry.items[0].snapshot, reader)
    );
  }
  for (const old of [page, originals]) {
    decodeAnalysisResultSnapshot(old.items[0].snapshot, 18);
  }
  const changed = JSON.parse(geometry.items[0].snapshot);
  changed.evidence_manifest.items[0].preparation.offset_x += 1;
  assertThrows(() => decodeAnalysisResultSnapshot(JSON.stringify(changed), 18));
});
const request = {
  schema_version: 1 as const,
  observation_id: page.observation_id,
  before_ordinal: null,
  limit: 20,
};
Deno.test("reader17 requires the V8 original discriminator and keeps V7 readable", () => {
  const result = decodeAnalysisResultSnapshot(originals.items[0].snapshot, 17);
  assertEquals(result.evidence_manifest.schema_version, 8);
  assertEquals(
    parseHistoryPage(originals, request, originals.owner_id, 17).items,
    originals.items,
  );
  assertEquals(
    decodeAnalysisResultSnapshot(page.items[0].snapshot, 17).evidence_manifest
      .schema_version,
    7,
  );
  for (const reader of [7, 8, 9, 10, 11, 13, 14, 15, 16] as const) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(originals.items[0].snapshot, reader)
    );
  }
  const changed = JSON.parse(originals.items[0].snapshot);
  changed.evidence_manifest.schema_version = 7;
  assertThrows(() => decodeAnalysisResultSnapshot(JSON.stringify(changed), 17));
  const value = structuredClone(state);
  value.observation_id = originals.observation_id;
  value.owner_id = originals.owner_id;
  value.selected_analysis_id = result.analysis_id;
  value.analysis.snapshot = originals.items[0].snapshot;
  const stateRequest = {
    schema_version: 1 as const,
    observation_id: originals.observation_id,
    analysis_id: null,
  };
  assertEquals(
    parseHistoryState(value, stateRequest, originals.owner_id, 17).analysis
      .snapshot,
    originals.items[0].snapshot,
  );
  assertThrows(() =>
    parseHistoryState(value, stateRequest, originals.owner_id, 16)
  );
});
Deno.test("reader16 binds ordinary baseline to exact original manifest and proof", () => {
  const result = decodeAnalysisResultSnapshot(page.items[0].snapshot, 16);
  assertEquals(result.evidence_manifest, original.evidence_manifest);
  assertEquals(
    parseHistoryPage(page, request, page.owner_id, 16).items,
    page.items,
  );
  for (const reader of [7, 8, 9, 10, 11, 13, 14, 15] as const) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(page.items[0].snapshot, reader)
    );
  }
  const value = structuredClone(state);
  value.observation_id = page.observation_id;
  value.owner_id = page.owner_id;
  value.selected_analysis_id = original.analysis_id;
  value.analysis.snapshot = page.items[0].snapshot;
  assertEquals(
    parseHistoryState(
      value,
      {
        schema_version: 1,
        observation_id: page.observation_id,
        analysis_id: null,
      },
      page.owner_id,
      16,
    ).analysis.snapshot,
    page.items[0].snapshot,
  );
});
Deno.test("ordinary baseline refuses altered selection, context, identities, roles and owner", () => {
  const changes: ((row: typeof original) => void)[] = [
    (r) => r.evidence_manifest.items[0].focus_region.x = 0.11,
    (r) => r.evidence_manifest.items[1].text = "Synthetic 🦋 context.",
    (r) => r.evidence_manifest.items[2].frames.reverse(),
    (r) => r.evidence_manifest.items[2].source.sha256 = "b".repeat(64),
    (r) => r.initial_evidence.generation = r.analysis_id,
    (r) => r.initial_evidence.scan_id = r.analysis_id,
    (r) => r.source_analysis_id = r.observation_id,
    (r) => r.ordinal = 2,
    (r) => r.initial_evidence.extra = true,
    (r) => delete r.initial_evidence,
    (r) => r.evidence_manifest.items[0].coordinate_basis = "original_image",
    (r) => r.evidence_manifest.items[0].prepared.media_id = r.analysis_id,
  ];
  for (const alter of changes) {
    const copy = structuredClone(original);
    alter(copy);
    assertThrows(() => decodeAnalysisResultSnapshot(JSON.stringify(copy), 16));
  }
  const copy = structuredClone(original);
  copy.initial_evidence.owner_id = "00000000-0000-4000-8000-000000000099";
  const changed = {
    ...page,
    items: [{ ordinal: 1, snapshot: JSON.stringify(copy) }],
  };
  assertThrows(() => parseHistoryPage(changed, request, page.owner_id, 16));
});
