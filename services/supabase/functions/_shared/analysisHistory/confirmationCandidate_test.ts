import { assertEquals, assertThrows } from "@std/assert";
import {
  parseAnalysisConfirmationReceipt,
  parseAnalysisConfirmationRequest,
  parseConfirmationPreparation,
} from "./confirmation.ts";

const legacy = {
  schema_version: 1,
  observation_id: "00000000-0000-4000-8000-000000000001",
  analysis_id: "00000000-0000-4000-8000-000000000002",
  operation_id: "00000000-0000-4000-8000-000000000003",
  expected_observation_revision: 12,
  expected_review_revision: 3,
  action: "confirm_name",
  scientific_name: "Fixtureus alternative",
} as const;
const request = {
  ...legacy,
  schema_version: 2,
  candidate_reference: {
    version: 1,
    analysis_id: legacy.analysis_id,
    representation: "stored_species_candidates_v1",
    ordinal: 1,
  },
} as const;

Deno.test("candidate confirmation retains exact provenance while v1 stays unchanged", () => {
  assertEquals(parseAnalysisConfirmationRequest(legacy), legacy);
  assertEquals(parseAnalysisConfirmationRequest(request), request);
  for (const original of [legacy, request]) {
    const expected = parseAnalysisConfirmationRequest(original);
    for (const outcome of ["revision_conflict", "not_verified"] as const) {
      const receipt = { ...original, outcome };
      assertEquals(
        parseAnalysisConfirmationReceipt(receipt, expected),
        receipt,
      );
    }
    const receipt = {
      ...original,
      outcome: "applied" as const,
      observation_revision: 13,
      review_revision: 4,
    };
    assertEquals(parseAnalysisConfirmationReceipt(receipt, expected), receipt);
    const prepared = {
      schema_version: 1 as const,
      status: "verify" as const,
      request: original,
      scientific_name: original.scientific_name,
    };
    assertEquals(parseConfirmationPreparation(prepared, expected), prepared);
  }
});

Deno.test("candidate identity rejects forged cross-analysis unbounded and unsupported references", () => {
  for (
    const changes of [
      { version: 2 },
      { analysis_id: legacy.observation_id },
      { representation: "display_candidates" },
      { ordinal: -1 },
      { ordinal: 5 },
      { ordinal: 0.5 },
      { ordinal: "1" },
      { ordinal: null },
      { name: legacy.scientific_name },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisConfirmationRequest({
        ...request,
        candidate_reference: { ...request.candidate_reference, ...changes },
      })
    );
  }
  for (
    const changes of [
      { schema_version: 1 },
      { schema_version: 3 },
      { action: "confirm_primary", scientific_name: null },
      { scientific_name: null },
      { scientific_name: " padded name " },
      { candidate_reference: null },
      { owner_id: legacy.observation_id },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisConfirmationRequest({ ...request, ...changes })
    );
  }
  const { candidate_reference: _reference, ...missing } = request;
  assertThrows(() => parseAnalysisConfirmationRequest(missing));
});

Deno.test("candidate receipt and preparation cannot drop rebase or substitute provenance", () => {
  const expected = parseAnalysisConfirmationRequest(request);
  const receipt = {
    ...request,
    outcome: "applied" as const,
    observation_revision: 13,
    review_revision: 4,
  };
  for (
    const changes of [
      { candidate_reference: { ...request.candidate_reference, ordinal: 0 } },
      { scientific_name: "Fixtureus different" },
      { operation_id: legacy.analysis_id },
      { expected_review_revision: 2 },
      { schema_version: 1 },
    ]
  ) {
    assertThrows(() =>
      parseAnalysisConfirmationReceipt({ ...receipt, ...changes }, expected)
    );
  }
  assertThrows(() =>
    parseConfirmationPreparation({
      schema_version: 1 as const,
      status: "verify" as const,
      request,
      scientific_name: "Fixtureus different",
    }, expected)
  );
  assertThrows(() =>
    parseAnalysisConfirmationReceipt(
      { ...legacy, outcome: "not_verified" },
      expected,
    )
  );
});
