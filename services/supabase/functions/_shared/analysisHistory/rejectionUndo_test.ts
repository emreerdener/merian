import { assertEquals, assertThrows } from "@std/assert";
import {
  parseRejectionUndoEligibility,
  parseRejectionUndoLookup,
} from "./rejectionUndo.ts";
import {
  parseAnalysisRejectionReceipt,
  parseAnalysisRejectionRequest,
} from "./review.ts";
const request = {
  schema_version: 1,
  observation_id: "00000000-0000-4000-8000-000000000001",
  analysis_id: "00000000-0000-4000-8000-000000000002",
  expected_observation_revision: 9,
  expected_review_revision: 3,
};
Deno.test("rejection Undo uses existing exact eight-field review wire", () => {
  const undo = parseAnalysisRejectionRequest({
    ...request,
    operation_id: "00000000-0000-4000-8000-000000000003",
    action: "undo",
    undo_operation_id: "00000000-0000-4000-8000-000000000004",
  });
  assertEquals(
    parseAnalysisRejectionReceipt({
      ...undo,
      outcome: "applied",
      observation_revision: 10,
      review_revision: 4,
    }, undo).action,
    "undo",
  );
  assertThrows(() =>
    parseAnalysisRejectionRequest({ ...undo, undo_operation_id: null })
  );
});
Deno.test("lookup returns only exact scoped rejection eligibility", () => {
  const exact = parseRejectionUndoLookup(request);
  const row = {
    ...exact,
    status: "available",
    rejection_operation_id: "00000000-0000-4000-8000-000000000004",
  } as const;
  assertEquals(parseRejectionUndoEligibility(row, exact), row);
  for (
    const changed of [
      { ...row, analysis_id: "00000000-0000-4000-8000-000000000009" },
      { ...row, expected_review_revision: 4 },
      { ...row, scientific_name: "private" },
      { ...row, rejection_operation_id: "invalid" },
    ]
  ) assertThrows(() => parseRejectionUndoEligibility(changed, exact));
  for (
    const reason of [
      "community_authority",
      "not_rejected",
      "receipt_unavailable",
      "rejection_changed",
      "revision_conflict",
    ]
  ) {
    assertEquals(
      parseRejectionUndoEligibility({
        ...exact,
        status: "unavailable",
        reason,
      }, exact).status,
      "unavailable",
    );
  }
  assertThrows(() =>
    parseRejectionUndoEligibility({
      ...exact,
      status: "unavailable",
      reason: "unknown",
    }, exact)
  );
  assertThrows(() =>
    parseRejectionUndoLookup({
      ...request,
      expected_review_revision: 2147483647,
    })
  );
});
