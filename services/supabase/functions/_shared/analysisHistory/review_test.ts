import { assertEquals, assertThrows } from "@std/assert";
import {
  parseAnalysisRejectionReceipt,
  parseAnalysisRejectionRequest,
} from "./review.ts";
const request = {
  schema_version: 1,
  observation_id: "00000000-0000-4000-8000-000000000001",
  analysis_id: "00000000-0000-4000-8000-000000000002",
  operation_id: "00000000-0000-4000-8000-000000000003",
  expected_observation_revision: 7,
  expected_review_revision: 2,
  action: "reject",
  undo_operation_id: null,
} as const;
Deno.test("analysis rejection contract refuses unbound or unsupported authority", () => {
  assertEquals(parseAnalysisRejectionRequest(request), request);
  for (
    const change of [
      { action: "confirm_primary" },
      { action: "carry" },
      { action: "undo" },
      { expected_review_revision: true },
      { expected_observation_revision: 2147483647 },
      { analysis_id: null },
      { owner_id: request.observation_id },
      { undo_operation_id: request.operation_id },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisRejectionRequest({ ...request, ...change })
    );
  }
  assertEquals(
    parseAnalysisRejectionRequest({
      ...request,
      action: "undo",
      undo_operation_id: request.operation_id,
    }).action,
    "undo",
  );
});
Deno.test("analysis review receipts bind all intent fields and both resulting revisions", () => {
  const expected = parseAnalysisRejectionRequest(request);
  const applied = {
    ...request,
    outcome: "applied",
    observation_revision: 8,
    review_revision: 3,
  } as const;
  const conflict = { ...request, outcome: "revision_conflict" } as const;
  assertEquals(parseAnalysisRejectionReceipt(applied, expected), applied);
  assertEquals(parseAnalysisRejectionReceipt(conflict, expected), conflict);
  for (
    const change of [
      { analysis_id: request.observation_id },
      { operation_id: request.analysis_id },
      { observation_revision: 9 },
      { review_revision: 2 },
      { expected_review_revision: 1 },
      { current_state: {} },
      { outcome: "unknown" },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisRejectionReceipt({ ...applied, ...change }, expected)
    );
  }
  assertThrows(() =>
    parseAnalysisRejectionReceipt({ ...conflict, review_revision: 3 }, expected)
  );
});
