import { assertEquals, assertThrows } from "@std/assert";
import {
  parseConfirmationUndoEligibility,
  parseConfirmationUndoLookup,
} from "./confirmationUndo.ts";
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
Deno.test("confirmation Undo uses existing exact eight-field review wire", () => {
  const undo = parseAnalysisRejectionRequest({
    ...request,
    operation_id: "00000000-0000-4000-8000-000000000003",
    action: "undo_confirmation",
    undo_operation_id: "00000000-0000-4000-8000-000000000004",
  });
  assertEquals(
    parseAnalysisRejectionReceipt({
      ...undo,
      outcome: "applied",
      observation_revision: 10,
      review_revision: 4,
    }, undo).action,
    "undo_confirmation",
  );
  assertThrows(() =>
    parseAnalysisRejectionRequest({ ...undo, undo_operation_id: null })
  );
});
Deno.test("lookup returns only exact scoped confirmation eligibility", () => {
  const exact = parseConfirmationUndoLookup(request);
  const row = {
    ...exact,
    status: "available",
    confirmation_operation_id: "00000000-0000-4000-8000-000000000004",
    confirmation_action: "confirm_name",
  } as const;
  assertEquals(parseConfirmationUndoEligibility(row, exact), row);
  for (
    const changed of [
      { ...row, confirmation_action: "reject" },
      { ...row, expected_review_revision: 4 },
      { ...row, scientific_name: "private" },
      { ...row, confirmation_operation_id: "invalid" },
    ]
  ) assertThrows(() => parseConfirmationUndoEligibility(changed, exact));
  for (
    const reason of [
      "community_authority",
      "not_confirmed",
      "receipt_unavailable",
      "confirmation_changed",
      "revision_conflict",
    ]
  ) {
    assertEquals(
      parseConfirmationUndoEligibility({
        ...exact,
        status: "unavailable",
        reason,
      }, exact).status,
      "unavailable",
    );
  }
  assertThrows(() =>
    parseConfirmationUndoEligibility({
      ...exact,
      status: "unavailable",
      reason: "unknown",
    }, exact)
  );
  assertThrows(() =>
    parseConfirmationUndoLookup({
      ...request,
      expected_review_revision: 2147483647,
    })
  );
});
