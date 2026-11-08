import { assertEquals, assertThrows } from "@std/assert";
import {
  parseAnalysisRetirementReceipt,
  parseAnalysisRetirementRequest,
} from "../_shared/analysisHistory/executionRetirement.ts";
const base = {
  schema_version: 1,
  operation_id: "00000000-0000-4000-8000-000000000001",
  observation_id: "00000000-0000-4000-8000-000000000002",
  analysis_id: "00000000-0000-4000-8000-000000000003",
  source_analysis_id: null,
  request_digest: "a".repeat(64),
};
Deno.test("retirement binds original request and one operation, including nullable source", () => {
  for (const source of [null, "00000000-0000-4000-8000-000000000004"]) {
    const request = parseAnalysisRetirementRequest({
      ...base,
      source_analysis_id: source,
    });
    const receipt = { ...request, state: "retired_before_dispatch" };
    assertEquals(parseAnalysisRetirementReceipt(receipt, request), receipt);
  }
});
Deno.test("retirement rejects malformed, rebound and nonterminal proof", () => {
  const request = parseAnalysisRetirementRequest(base);
  for (
    const value of [
      null,
      [],
      {},
      { ...base, extra: true },
      { ...base, operation_id: base.analysis_id },
      { ...base, operation_id: true },
      { ...base, request_digest: "A".repeat(64) },
      { ...base, source_analysis_id: base.observation_id },
    ]
  ) {
    assertThrows(() => parseAnalysisRetirementRequest(value));
  }
  const receipt = { ...request, state: "retired_before_dispatch" };
  for (
    const value of [
      null,
      {},
      { ...receipt, state: "absent" },
      { ...receipt, state: "failed_terminal" },
      { ...receipt, state: "admitted" },
      { ...receipt, state: "dispatched" },
      { ...receipt, extra: true },
      { ...receipt, request_digest: "b".repeat(64) },
      { ...receipt, operation_id: "00000000-0000-4000-8000-000000000009" },
      {
        ...receipt,
        source_analysis_id: "00000000-0000-4000-8000-000000000008",
      },
    ]
  ) {
    assertThrows(() => parseAnalysisRetirementReceipt(value, request));
  }
  for (const key of Object.keys(receipt)) {
    const missing: Record<string, unknown> = { ...receipt };
    delete missing[key];
    assertThrows(() => parseAnalysisRetirementReceipt(missing, request));
  }
});
