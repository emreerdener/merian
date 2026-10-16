import { assertEquals, assertThrows } from "@std/assert";
import { parseAnalysisIdentity } from "../_shared/analysisHistory/contract.ts";
import { parseAnalysisExecutionStatus } from "../_shared/analysisHistory/executionStatus.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const request = parseAnalysisIdentity({
  schema_version: 1,
  observation_id: "00000000-0000-4000-8000-000000000002",
  analysis_id: "00000000-0000-4000-8000-000000000003",
  source_analysis_id: "00000000-0000-4000-8000-000000000004",
  request_digest: "a".repeat(64),
});
Deno.test("execution status retains exact identity in every state, including absence", () => {
  for (
    const state of [
      "absent",
      "admitted",
      "dispatched",
      "draft",
      "complete",
      "failed_terminal",
    ]
  ) {
    for (const source of [request.source_analysis_id, null]) {
      const expected = { ...request, source_analysis_id: source };
      const reply = { ...expected, owner_id: owner, state };
      assertEquals(parseAnalysisExecutionStatus(reply, expected, owner), reply);
    }
  }
});
Deno.test("execution status rejects malformed or mismatched scope, never interpreting it as absence", () => {
  const reply = { ...request, owner_id: owner, state: "absent" };
  for (
    const value of [
      null,
      [],
      {},
      { ...reply, extra: true },
      { ...reply, schema_version: true },
      { ...reply, state: "held" },
      { ...reply, owner_id: request.analysis_id },
      { ...reply, observation_id: request.analysis_id },
      { ...reply, analysis_id: owner },
      { ...reply, source_analysis_id: null },
      { ...reply, request_digest: "b".repeat(64) },
      { ...reply, request_digest: "A".repeat(64) },
    ]
  ) assertThrows(() => parseAnalysisExecutionStatus(value, request, owner));
  for (const key of Object.keys(reply)) {
    const missing = { ...reply } as Record<string, unknown>;
    delete missing[key];
    assertThrows(() => parseAnalysisExecutionStatus(missing, request, owner));
  }
});
