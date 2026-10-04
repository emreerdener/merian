import {
  exactObject,
  historyRevision,
  historyUUID,
  invalidHistory,
  parseSelectionRequest,
  type SelectionRequest,
} from "./contract.ts";

const requestKeys = [
  "schema_version",
  "observation_id",
  "analysis_id",
  "operation_id",
  "expected_observation_revision",
  "expected_review_revision",
  "action",
  "undo_operation_id",
] as const;
export interface AnalysisRejectionRequest extends SelectionRequest {
  action: "reject" | "undo";
  undo_operation_id: string | null;
}

/** Prepared protocol 9 RPC contract; no ordinary native caller is enabled. */
export function parseAnalysisRejectionRequest(
  value: unknown,
): AnalysisRejectionRequest {
  const row = exactObject(value, requestKeys);
  const { action, undo_operation_id, ...selection } = row;
  if (action !== "reject" && action !== "undo") return invalidHistory();
  if (action === "reject" && undo_operation_id !== null) {
    return invalidHistory();
  }
  return Object.freeze({
    ...parseSelectionRequest(selection),
    action,
    undo_operation_id: action === "undo"
      ? historyUUID(undo_operation_id)
      : null,
  });
}
export type AnalysisRejectionReceipt =
  & AnalysisRejectionRequest
  & (
    | { outcome: "revision_conflict" }
    | {
      outcome: "applied";
      observation_revision: number;
      review_revision: number;
    }
  );

/** A receipt is proof of an outcome, never a replacement for current state. */
export function parseAnalysisRejectionReceipt(
  value: unknown,
  expected: AnalysisRejectionRequest,
): AnalysisRejectionReceipt {
  const outcome = (value as { outcome?: unknown } | null)?.outcome;
  if (outcome !== "applied" && outcome !== "revision_conflict") {
    return invalidHistory();
  }
  const row = exactObject(value, [
    ...requestKeys,
    "outcome",
    ...(outcome === "applied"
      ? ["observation_revision", "review_revision"]
      : []),
  ]);
  const request = parseAnalysisRejectionRequest(
    Object.fromEntries(requestKeys.map((key) => [key, row[key]])),
  );
  if (
    JSON.stringify(request) !==
      JSON.stringify(parseAnalysisRejectionRequest(expected))
  ) return invalidHistory();
  if (outcome === "revision_conflict") return { ...request, outcome };
  const observation = historyRevision(row.observation_revision);
  const review = historyRevision(row.review_revision);
  if (
    observation !== request.expected_observation_revision + 1 ||
    review !== request.expected_review_revision + 1
  ) return invalidHistory();
  return {
    ...request,
    outcome,
    observation_revision: observation,
    review_revision: review,
  };
}
