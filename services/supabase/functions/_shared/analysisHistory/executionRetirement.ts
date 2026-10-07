import {
  exactObject,
  historyUUID,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";

/** Original execution identity plus the one retained retirement operation. */
export function parseAnalysisRetirementRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "operation_id",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
  ]);
  const { operation_id, ...identity } = row;
  const request = parseAnalysisIdentity(identity);
  const operation = historyUUID(operation_id);
  if (
    [request.observation_id, request.analysis_id, request.source_analysis_id]
      .includes(operation)
  ) {
    return invalidHistory();
  }
  return Object.freeze({ ...request, operation_id: operation });
}
export type AnalysisRetirementRequest = ReturnType<
  typeof parseAnalysisRetirementRequest
>;

/** Only this exact saved terminal receipt proves admitted work was retired. */
export function parseAnalysisRetirementReceipt(
  value: unknown,
  expected: AnalysisRetirementRequest,
) {
  const row = exactObject(value, [
    "schema_version",
    "operation_id",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "state",
  ]);
  const { state, ...identity } = row;
  const request = parseAnalysisRetirementRequest(identity);
  if (
    state !== "retired_before_dispatch" ||
    JSON.stringify(request) !==
      JSON.stringify(parseAnalysisRetirementRequest(expected))
  ) {
    return invalidHistory();
  }
  return Object.freeze({ ...request, state });
}
