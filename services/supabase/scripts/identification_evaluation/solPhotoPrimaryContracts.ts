/** Separate experiment identities. Historical photo-model plans remain closed. */
import { hash, number, unique } from "./runContracts.ts";
import {
  array,
  fields,
  id,
  requireCondition as check,
  token,
} from "./validation.ts";

export const SOL_PRIMARY_SCREEN_POLICY = "primary_reference_limits_v1";
export interface SolPrimaryPlan {
  version: "sol_photo_primary_plan_v1";
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
  screeningPolicy: typeof SOL_PRIMARY_SCREEN_POLICY;
  inputApproval: null | {
    provider: "openai";
    corpusDigest: string;
    caseIds: string[];
    recordRef: string;
  };
}
export function parseSolPrimaryPlan(value: unknown): SolPrimaryPlan {
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
    v.version === "sol_photo_primary_plan_v1" &&
      v.screeningPolicy === SOL_PRIMARY_SCREEN_POLICY,
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
  return structuredClone(v) as unknown as SolPrimaryPlan;
}
