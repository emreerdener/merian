import { isScientificName } from "../identify/speciesVerification.ts";
import {
  exactObject,
  historyRevision,
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
  "scientific_name",
] as const;

export interface AnalysisConfirmationRequest extends SelectionRequest {
  action: "confirm_primary" | "confirm_name";
  scientific_name: string | null;
}

export function parseAnalysisConfirmationRequest(
  value: unknown,
): AnalysisConfirmationRequest {
  const row = exactObject(value, requestKeys);
  const { action, scientific_name, ...selection } = row;
  if (action !== "confirm_primary" && action !== "confirm_name") {
    return invalidHistory();
  }
  if (
    action === "confirm_primary"
      ? scientific_name !== null
      : !isScientificName(scientific_name)
  ) {
    return invalidHistory();
  }
  return Object.freeze({
    ...parseSelectionRequest(selection),
    action,
    scientific_name: scientific_name as string | null,
  });
}

export type AnalysisConfirmationReceipt =
  & AnalysisConfirmationRequest
  & (
    | { outcome: "revision_conflict" | "not_verified" }
    | {
      outcome: "applied";
      observation_revision: number;
      review_revision: number;
    }
  );

function sameRequest(
  value: unknown,
  expected: AnalysisConfirmationRequest,
): AnalysisConfirmationRequest {
  const request = parseAnalysisConfirmationRequest(value);
  if (
    JSON.stringify(request) !==
      JSON.stringify(parseAnalysisConfirmationRequest(expected))
  ) return invalidHistory();
  return request;
}

/** Immutable outcome, not evidence of current authority. Always reread current state. */
export function parseAnalysisConfirmationReceipt(
  value: unknown,
  expected: AnalysisConfirmationRequest,
): AnalysisConfirmationReceipt {
  const outcome = (value as { outcome?: unknown } | null)?.outcome;
  if (
    outcome !== "applied" && outcome !== "revision_conflict" &&
    outcome !== "not_verified"
  ) return invalidHistory();
  const row = exactObject(value, [
    ...requestKeys,
    "outcome",
    ...(outcome === "applied"
      ? ["observation_revision", "review_revision"]
      : []),
  ]);
  const request = sameRequest(
    Object.fromEntries(requestKeys.map((key) => [key, row[key]])),
    expected,
  );
  if (outcome !== "applied") return { ...request, outcome };
  const observation = historyRevision(row.observation_revision),
    review = historyRevision(row.review_revision);
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

export type ConfirmationPreparation =
  | {
    schema_version: 1;
    status: "verify";
    request: AnalysisConfirmationRequest;
    scientific_name: string;
  }
  | {
    schema_version: 1;
    status: "complete";
    receipt: AnalysisConfirmationReceipt;
  };

export function parseConfirmationPreparation(
  value: unknown,
  expected: AnalysisConfirmationRequest,
): ConfirmationPreparation {
  const status = (value as { status?: unknown } | null)?.status;
  if (status !== "verify" && status !== "complete") return invalidHistory();
  const row = exactObject(value, [
    "schema_version",
    "status",
    ...(status === "verify" ? ["request", "scientific_name"] : ["receipt"]),
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  if (status === "complete") {
    return {
      schema_version: 1,
      status,
      receipt: parseAnalysisConfirmationReceipt(row.receipt, expected),
    };
  }
  const request = sameRequest(row.request, expected);
  if (
    !isScientificName(row.scientific_name) ||
    (request.action === "confirm_name" &&
      row.scientific_name !== request.scientific_name)
  ) return invalidHistory();
  return {
    schema_version: 1,
    status,
    request,
    scientific_name: row.scientific_name,
  };
}
