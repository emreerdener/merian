import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";
import { parseSavedHistoryEnrollment } from "./savedIdentification.ts";

export function parseBaselineRecoveryRequest(value: unknown) {
  const row = exactObject(value, ["schema_version", "observation_id"]);
  if (row.schema_version !== 1) return invalidHistory();
  return Object.freeze({
    schema_version: 1 as const,
    observation_id: historyUUID(row.observation_id),
  });
}

/** Same domain and exact UTF-8 bytes as the existing native association. */
export async function enrollmentBaselineDigest(snapshot: string) {
  const bytes = new TextEncoder().encode(
    "merian.observation-history.enrollment-baseline.v1\n" + snapshot,
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

/** Historical association only. No selection, review or local intent is inferred. */
export async function parseBaselineRecovery(
  value: unknown,
  request: ReturnType<typeof parseBaselineRecoveryRequest>,
  ownerID: string,
) {
  const expected = parseBaselineRecoveryRequest(request);
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "baseline_analysis_id",
    "snapshot",
    "snapshot_sha256",
  ]);
  if (new TextEncoder().encode(JSON.stringify(row)).length > 4194304) {
    return invalidHistory();
  }
  const association = parseSavedHistoryEnrollment(
    {
      schema_version: row.schema_version,
      owner_id: row.owner_id,
      observation_id: row.observation_id,
      baseline_analysis_id: row.baseline_analysis_id,
    },
    ownerID,
    expected.observation_id,
  );
  if (typeof row.snapshot !== "string") return invalidHistory();
  const result = decodeAnalysisResultSnapshot(row.snapshot, 9);
  if (
    result.schema_version !== 3 || result.ordinal !== 1 ||
    result.observation_id !== expected.observation_id ||
    result.analysis_id !== association.baseline_analysis_id ||
    typeof row.snapshot_sha256 !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.snapshot_sha256) ||
    await enrollmentBaselineDigest(row.snapshot) !== row.snapshot_sha256
  ) return invalidHistory();
  return Object.freeze({
    ...association,
    snapshot: row.snapshot,
    snapshot_sha256: row.snapshot_sha256,
  });
}
