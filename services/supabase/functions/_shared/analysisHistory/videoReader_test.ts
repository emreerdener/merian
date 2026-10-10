import { assertEquals, assertThrows } from "@std/assert";
import fixture from "./fixtures/video-result-v5.json" with { type: "json" };
import page from "./fixtures/page-v1.json" with { type: "json" };
import { decodeAnalysisResultSnapshot } from "./result.ts";
import { parseHistoryPage } from "./page.ts";
import { parseHistoryState } from "./state.ts";

import manifests from "./fixtures/video-manifest-v4.json" with { type: "json" };
const vectors = fixture.cases.map((test) => ({
  ...test,
  snapshot: {
    ...fixture.base_snapshot,
    schema_version: test.schema_version,
    source_analysis_id: test.source_analysis_id,
    observation_id: manifests[test.manifest_index].observation_id,
    analysis_id: manifests[test.manifest_index].analysis_id,
    evidence_manifest: manifests[test.manifest_index].manifest,
  },
}));

Deno.test("reader11 video result shared accepted/rejected vectors preserve bytes", () => {
  for (const vector of vectors) {
    const snapshot = JSON.stringify(vector.snapshot, null, 2);
    const request = {
      schema_version: 1 as const,
      observation_id: vector.snapshot.observation_id,
      before_ordinal: null,
      limit: 20,
    };
    const value = {
      ...page,
      observation_id: request.observation_id,
      items: [{ ordinal: 1, snapshot }],
    };
    if (vector.valid) {
      assertEquals(
        decodeAnalysisResultSnapshot(snapshot, 11).schema_version,
        5,
        vector.name,
      );
      assertEquals(
        parseHistoryPage(value, request, page.owner_id, 11).items[0].snapshot,
        snapshot,
      );
      const stateRequest = {
        schema_version: 1 as const,
        observation_id: request.observation_id,
        analysis_id: vector.snapshot.analysis_id,
      };
      const state = {
        schema_version: 1,
        owner_id: page.owner_id,
        observation_id: request.observation_id,
        state_revision: 10,
        selection_initialized: true,
        selected_analysis_id: vector.snapshot.source_analysis_id,
        analysis: {
          snapshot,
          review_revision: 0,
          review_snapshot: {
            ai_identification_review: null,
            confirmed_species_identity: null,
            confirmed_species_identity_revision: 0,
            confirmed_species_id: null,
            user_identification_override: null,
            user_confirmed_identification: false,
            user_review_state: "unreviewed",
          },
        },
      };
      assertEquals(
        parseHistoryState(state, stateRequest, page.owner_id, 11).analysis
          .snapshot,
        snapshot,
      );
      for (const reader of [7, 8, 9, 10] as const) {
        assertThrows(() => decodeAnalysisResultSnapshot(snapshot, reader));
      }
      for (const reader of [9, 10] as const) {
        assertThrows(() =>
          parseHistoryState(state, stateRequest, page.owner_id, reader)
        );
      }
    } else {
      assertThrows(
        () => decodeAnalysisResultSnapshot(snapshot, 11),
        Error,
        undefined,
        vector.name,
      );
      assertThrows(() => parseHistoryPage(value, request, page.owner_id, 11));
    }
  }
});

Deno.test("reader11 keeps exact legacy history bytes and rejects unadvertised capability", () => {
  const request = {
    schema_version: 1 as const,
    observation_id: page.observation_id,
    before_ordinal: null,
    limit: 20,
  };
  assertEquals(
    parseHistoryPage(page, request, page.owner_id, 11).items,
    page.items,
  );
  assertThrows(() =>
    decodeAnalysisResultSnapshot(JSON.stringify(vectors[0].snapshot), 12 as 11)
  );
  assertThrows(() => decodeAnalysisResultSnapshot(" ".repeat(1048577), 11));
});
