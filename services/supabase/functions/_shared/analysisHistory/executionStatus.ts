import {
  type AnalysisIdentity,
  exactObject,
  historyUUID,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";

/** A status observation never grants dispatch, retirement or replacement. */
export function parseAnalysisExecutionStatus(
  value: unknown,
  expected: AnalysisIdentity,
  ownerID: string,
) {
  const request = parseAnalysisIdentity(expected);
  const owner = historyUUID(ownerID);
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
    "state",
  ]);
  const { owner_id, state, ...identity } = row;
  const actual = parseAnalysisIdentity(identity);
  if (
    owner_id !== owner ||
    JSON.stringify(actual) !== JSON.stringify(request) ||
    (state !== "absent" && state !== "admitted" && state !== "dispatched" &&
      state !== "draft" && state !== "complete" && state !== "failed_terminal")
  ) return invalidHistory();
  return Object.freeze({ ...actual, owner_id: owner, state });
}
