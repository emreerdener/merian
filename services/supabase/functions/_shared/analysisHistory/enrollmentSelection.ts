import { exactObject, invalidHistory } from "./contract.ts";
import {
  parseBaselineRecovery,
  parseBaselineRecoveryRequest,
} from "./baselineRecovery.ts";
import { parseHistoryState } from "./state.ts";

/** Atomic server read, not a client join or authority to request selection. */
export async function parseEnrollmentSelection(
  value: unknown,
  observationID: string,
  ownerID: string,
  baselineID: string,
) {
  const request = parseBaselineRecoveryRequest({
    schema_version: 1,
    observation_id: observationID,
  });
  const row = exactObject(value, [
    "schema_version",
    "baseline_sha256",
    "baseline_state",
    "selected_state",
  ]);
  if (
    row.schema_version !== 1 ||
    new TextEncoder().encode(JSON.stringify(row)).length > 4194304
  ) return invalidHistory();
  const baseline = parseHistoryState(
    row.baseline_state,
    { ...request, analysis_id: baselineID },
    ownerID,
    11,
  );
  const selected = parseHistoryState(
    row.selected_state,
    { ...request, analysis_id: null },
    ownerID,
    11,
  );
  if (
    baseline.state_revision !== selected.state_revision ||
    baseline.selected_analysis_id !== selected.selected_analysis_id
  ) return invalidHistory();
  const association = await parseBaselineRecovery(
    {
      schema_version: 1,
      owner_id: ownerID,
      observation_id: observationID,
      baseline_analysis_id: baselineID,
      snapshot: baseline.analysis.snapshot,
      snapshot_sha256: row.baseline_sha256,
    },
    request,
    ownerID,
  );
  if (
    baselineID === selected.selected_analysis_id &&
    JSON.stringify(baseline) !== JSON.stringify(selected)
  ) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    baseline_sha256: association.snapshot_sha256,
    baseline_state: baseline,
    selected_state: selected,
  });
}
