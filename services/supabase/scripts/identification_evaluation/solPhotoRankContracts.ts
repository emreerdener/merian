/** Separate experiment identities. Historical photo-model plans remain closed. */
import { hash, number, timestamp, unique } from "./runContracts.ts";
import {
  array,
  fields,
  id,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";

export const SOL_RANK_SCREEN_POLICY = "sol_rank_mapping_and_reference_gaps_v1";
export interface SolRankPlan {
  version: "sol_photo_rank_plan_v1";
  id: string;
  corpusDigest: string;
  taxonomyDigest: string;
  factsDigest: string;
  pricingDigest: string;
  preparationDigest: string;
  referenceReviewDigest: string;
  screenCaseIds: string[];
  challengeCaseIds: string[];
  maxCalls: 18;
  attemptsPerAssignment: 1;
  budgetUsd: number;
  screeningPolicy: typeof SOL_RANK_SCREEN_POLICY;
  inputApproval: null | {
    provider: "openai";
    corpusDigest: string;
    caseIds: string[];
    recordRef: string;
  };
}
export function parseSolRankPlan(value: unknown): SolRankPlan {
  const v = fields(value, [
    "version",
    "id",
    "corpusDigest",
    "taxonomyDigest",
    "factsDigest",
    "pricingDigest",
    "preparationDigest",
    "referenceReviewDigest",
    "screenCaseIds",
    "challengeCaseIds",
    "maxCalls",
    "attemptsPerAssignment",
    "budgetUsd",
    "screeningPolicy",
    "inputApproval",
  ]);
  check(
    v.version === "sol_photo_rank_plan_v1" &&
      v.screeningPolicy === SOL_RANK_SCREEN_POLICY,
  );
  token(v.id);
  for (
    const key of [
      "corpusDigest",
      "taxonomyDigest",
      "factsDigest",
      "pricingDigest",
      "preparationDigest",
      "referenceReviewDigest",
    ]
  ) hash(v[key]);
  const cases = [
    ...array(v.screenCaseIds, 6, 6),
    ...array(v.challengeCaseIds, 6, 6),
  ];
  cases.forEach((c) => id(c, "c"));
  unique(cases);
  check(v.maxCalls === 18 && v.attemptsPerAssignment === 1);
  // Two Sol profiles need a new full-context allowance, never an inherited budget.
  number(v.budgetUsd, 0.01, 110);
  if (v.inputApproval !== null) {
    const a = fields(v.inputApproval, [
      "provider",
      "corpusDigest",
      "caseIds",
      "recordRef",
    ]);
    check(a.provider === "openai" && a.corpusDigest === v.corpusDigest);
    token(a.recordRef);
    const approved = array(a.caseIds, 12, 12);
    approved.forEach((c) => id(c, "c"));
    unique(approved);
    check(approved.every((c) => cases.includes(c)));
  }
  return structuredClone(v) as unknown as SolRankPlan;
}

export interface SolRankReferenceReview {
  version: "sol_photo_rank_reference_review_v1";
  corpusDigest: string;
  taxonomyDigest: string;
  factsDigest: string;
  method: "assistant_input_review_v1";
  reviewerRef: string;
  reviewedAt: string;
  referenceStatus:
    | "provisional_reused_development_cases"
    | "synthetic_mechanics_only";
  catalogCoverage: "finite_not_exhaustive";
  independentTruthVerified: false;
  cases: {
    caseId: string;
    inputDigest: string;
    referenceDigest: string;
    factsDigest: string;
    identitySupport: "usable_provisional" | "limited_reference";
    missingEvidenceRecorded: true;
  }[];
}
export function parseSolRankReferenceReview(
  value: unknown,
): SolRankReferenceReview {
  const v = fields(value, [
    "version",
    "corpusDigest",
    "taxonomyDigest",
    "factsDigest",
    "method",
    "reviewerRef",
    "reviewedAt",
    "referenceStatus",
    "catalogCoverage",
    "independentTruthVerified",
    "cases",
  ]);
  check(
    v.version === "sol_photo_rank_reference_review_v1" &&
      v.method === "assistant_input_review_v1" &&
      v.catalogCoverage === "finite_not_exhaustive" &&
      v.independentTruthVerified === false,
  );
  for (const key of ["corpusDigest", "taxonomyDigest", "factsDigest"]) {
    hash(v[key]);
  }
  token(v.reviewerRef);
  timestamp(v.reviewedAt);
  member(v.referenceStatus, [
    "provisional_reused_development_cases",
    "synthetic_mechanics_only",
  ]);
  const cases = array(v.cases, 12, 12).map((raw) => {
    const c = fields(raw, [
      "caseId",
      "inputDigest",
      "referenceDigest",
      "factsDigest",
      "identitySupport",
      "missingEvidenceRecorded",
    ]);
    id(c.caseId, "c");
    for (const k of ["inputDigest", "referenceDigest", "factsDigest"]) {
      hash(c[k]);
    }
    member(c.identitySupport, ["usable_provisional", "limited_reference"]);
    check(c.missingEvidenceRecorded === true);
    return c;
  });
  unique(cases.map((c) => c.caseId));
  return structuredClone(v) as unknown as SolRankReferenceReview;
}
