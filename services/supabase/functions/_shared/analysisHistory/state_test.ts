import { assertEquals, assertThrows } from "@std/assert";
import { HistoryError } from "./contract.ts";
import {
  parseHistoryReview,
  parseHistoryState,
  parseHistoryStateRequest,
} from "./state.ts";
const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/state-v1.json", import.meta.url)),
);
const request = {
  schema_version: 1 as const,
  observation_id: fixture.observation_id,
  analysis_id: null,
};
Deno.test("state read retains result bytes and keeps selected authority separate", () => {
  const state = parseHistoryState(fixture, request, fixture.owner_id);
  assertEquals(state, fixture);
  assertEquals(parseHistoryStateRequest(request), request);
});
Deno.test("explicit target preview never implies selection or another result's review", () => {
  const selected = "00000000-0000-4000-8000-000000000099";
  const preview = { ...fixture, selected_analysis_id: selected };
  assertThrows(
    () => parseHistoryState(preview, request, fixture.owner_id),
    HistoryError,
  );
  const state = parseHistoryState(preview, {
    ...request,
    analysis_id: fixture.selected_analysis_id,
  }, fixture.owner_id);
  assertEquals(state.selected_analysis_id, selected);
  assertEquals(state.analysis, fixture.analysis);
});
Deno.test("state read rejects forged identity revision and mutable result fields", () => {
  for (
    const patch of [
      { owner_id: request.observation_id },
      { observation_id: fixture.owner_id },
      { selected_analysis_id: request.observation_id },
      { selection_initialized: false },
      { state_revision: 0 },
      { state_revision: true },
      { state_revision: 2147483647 },
      { extra: true },
      { analysis: { ...fixture.analysis, review_revision: -1 } },
      {
        analysis: {
          ...fixture.analysis,
          review_snapshot: {
            ...fixture.analysis.review_snapshot,
            private_notes: "must not disclose",
          },
        },
      },
    ]
  ) {
    assertThrows(
      () =>
        parseHistoryState({ ...fixture, ...patch }, request, fixture.owner_id),
      HistoryError,
    );
  }
  for (
    const patch of [{ schema_version: 2 }, { analysis_id: true }, {
      analysis_id: request.observation_id,
    }, { owner_id: fixture.owner_id }]
  ) {
    assertThrows(
      () => parseHistoryStateRequest({ ...request, ...patch }),
      HistoryError,
    );
  }
});
Deno.test("legacy saved review survives without manufacturing verified identity", () => {
  const review = {
    ...fixture.analysis.review_snapshot,
    confirmed_species_id: "00000000-0000-4000-8000-000000000098",
    user_identification_override: "Saved correction",
    user_review_state: "user_overridden",
  };
  assertEquals(parseHistoryReview(review), review);
  for (
    const patch of [
      { user_confirmed_identification: 1 },
      { user_review_state: "confirmed" },
      { user_review_state: ["unreviewed"] },
      { confirmed_species_identity_revision: -1 },
      { ai_identification_review: {} },
      { confirmed_species_identity: {} },
      { user_identification_override: "a".repeat(1025) },
    ]
  ) {
    assertThrows(
      () => parseHistoryReview({ ...review, ...patch }),
      HistoryError,
    );
  }
});

Deno.test("state authority validates nested AI byte and UTF-16 bounds without losing rejection", () => {
  const ai = {
    version: 1 as const,
    revision: 2,
    state: "ai_rejected" as const,
    origin_scan_id: request.observation_id,
    origin_identification: {
      scientific_name: "Saved fixture",
      common_name: null,
    },
    operation_id: null,
    operation_digest: null,
    community: null,
  };
  const review = {
    ...fixture.analysis.review_snapshot,
    ai_identification_review: ai,
  };
  assertEquals(parseHistoryReview(review).ai_identification_review, ai);
  for (const label of ["e\u0301".repeat(100), "e" + "\u0301".repeat(5000)]) {
    assertThrows(
      () =>
        parseHistoryReview({
          ...review,
          ai_identification_review: {
            ...ai,
            origin_identification: {
              ...ai.origin_identification,
              scientific_name: label,
            },
          },
        }),
      HistoryError,
    );
  }
});
