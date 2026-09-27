/** Reviewer facts are private inputs. Only bound enum assessments may be journaled. */
import {
  array,
  fields,
  id,
  integer,
  member,
  requireCondition as check,
  text,
  token,
} from "./validation.ts";
import { hash, timestamp, unique } from "./runContracts.ts";
import { fingerprintJson } from "./evidence.ts";

export const CRITERIA = [
  "grounding",
  "requiredInformation",
  "uncertainty",
] as const;
export const FAIL_REASONS = {
  grounding: ["invented_evidence", "contradicted_evidence"],
  requiredInformation: ["missing_decision_reason", "generic_justification"],
  uncertainty: [
    "unsupported_certainty",
    "unsupported_specificity",
    "missing_limitation",
  ],
} as const;
export const UNASSESSED_REASONS = [
  "insufficient_reference",
  "reviewer_unsure",
  "review_unavailable",
] as const;
export const RUBRIC = {
  version: "explanation_rubric_v1",
  criteria: {
    grounding:
      "Each material explanatory claim is supported by the observation or reviewed facts. Invented or contradicted evidence fails; unverifiable claims are not assessable.",
    requiredInformation:
      "Specific reasons connect the observation to the decision or abstention and preserve applicable requirements. Generic or circular justification fails.",
    uncertainty:
      "Wording and rank reflect evidence limits. Unsupported certainty or specificity and concealed limitations fail.",
  },
  failReasons: FAIL_REASONS,
  unassessedReasons: UNASSESSED_REASONS,
} as const;
export interface Rating {
  status: "pass" | "fail" | "not_assessable";
  reason: string;
}
export type Ratings = Record<typeof CRITERIA[number], Rating>;
export function parseRatings(value: unknown): Ratings {
  const v = fields(value, CRITERIA);
  for (const key of CRITERIA) {
    const rating = fields(v[key], ["status", "reason"]);
    member(rating.status, ["pass", "fail", "not_assessable"]);
    member(
      rating.reason,
      rating.status === "pass"
        ? ["supported"]
        : rating.status === "fail"
        ? FAIL_REASONS[key]
        : UNASSESSED_REASONS,
    );
  }
  return structuredClone(v) as unknown as Ratings;
}
export const ratingsPass = (ratings: Ratings) =>
  CRITERIA.every((c) => ratings[c].status === "pass");
export const unavailableRatings = (): Ratings =>
  Object.fromEntries(
    CRITERIA.map((
      c,
    ) => [c, { status: "not_assessable", reason: "review_unavailable" }]),
  ) as Ratings;
export const REQUIREMENTS = [
  "decision_evidence",
  "rank_limit",
  "abstention_reason",
  "non_biological_reason",
] as const;
export interface FactCard {
  caseId: string;
  inputDigest: string;
  observed: string[];
  missing: string[];
  acceptableReasons: string[];
  rankLimit: string;
  requirements: typeof REQUIREMENTS[number][];
}
export function parseFactCards(
  value: unknown,
): { version: "explanation_facts_v1"; cards: FactCard[] } {
  const v = fields(value, ["version", "cards"]);
  check(v.version === "explanation_facts_v1");
  const cards = array(v.cards, 1, 8).map((raw) => {
    const c = fields(raw, [
      "caseId",
      "inputDigest",
      "observed",
      "missing",
      "acceptableReasons",
      "rankLimit",
      "requirements",
    ]);
    id(c.caseId, "c");
    hash(c.inputDigest);
    for (const key of ["observed", "missing", "acceptableReasons"]) {
      array(c[key], key === "missing" ? 0 : 1, 16).forEach((v) => text(v, 500));
    }
    text(c.rankLimit, 500);
    const required = array(c.requirements, 1, REQUIREMENTS.length);
    required.forEach((v) => member(v, REQUIREMENTS));
    unique(required);
    check(required.includes("decision_evidence"));
    return c as unknown as FactCard;
  });
  unique(cards.map((c) => c.caseId));
  return { version: "explanation_facts_v1", cards };
}
interface ReviewFactsPlan {
  rubricDigest: string;
  factsDigest: string;
  reviewerRef: string;
  timeoutMs: number;
  cards: { caseId: string; digest: string }[];
}
export type ReviewPlan =
  & ReviewFactsPlan
  & (
    | { calibrationDigest: string; method?: never; delegationRef?: never }
    | {
      calibrationDigest: null;
      method: "assistant_local_v1";
      delegationRef: string;
    }
  );
export function parseReviewPlan(value: unknown, assistant = false): ReviewPlan {
  const v = fields(value, [
    ...(assistant ? ["method", "delegationRef"] : []),
    "rubricDigest",
    "factsDigest",
    "calibrationDigest",
    "reviewerRef",
    "timeoutMs",
    "cards",
  ]);
  for (const key of ["rubricDigest", "factsDigest"]) {
    hash(v[key]);
  }
  if (assistant) {
    check(v.method === "assistant_local_v1" && v.calibrationDigest === null);
    token(v.delegationRef);
  } else hash(v.calibrationDigest);
  token(v.reviewerRef);
  integer(v.timeoutMs, 60000, 600000);
  const cards = array(v.cards, 1, 8).map((raw) => {
    const c = fields(raw, ["caseId", "digest"]);
    id(c.caseId, "c");
    hash(c.digest);
    return c;
  });
  unique(cards.map((c) => c.caseId));
  return v as unknown as ReviewPlan;
}
export interface AssessmentBinding {
  planDigest: string;
  runDigest: string;
  key: string;
  requestDigest: string;
  profileId: string;
  profileDigest: string;
  inputDigest: string;
  factCardDigest: string;
  resultDigest: string;
  calibrationDigest: string | null;
  rubricDigest: string;
  reviewerRef: string;
}
export interface ExplanationAssessment {
  version: "explanation_assessment_v1" | "explanation_assessment_v2";
  binding: AssessmentBinding;
  method: "owner_local_v1" | "assistant_local_v1" | "synthetic_fixture_v1";
  ratings: Ratings;
}
export function parseAssessment(value: unknown): ExplanationAssessment {
  const v = fields(value, ["version", "binding", "method", "ratings"]);
  const assistant = v.version === "explanation_assessment_v2";
  check(assistant || v.version === "explanation_assessment_v1");
  member(
    v.method,
    assistant
      ? ["assistant_local_v1", "synthetic_fixture_v1"] as const
      : ["owner_local_v1", "synthetic_fixture_v1"] as const,
  );
  const b = fields(v.binding, [
    "planDigest",
    "runDigest",
    "key",
    "requestDigest",
    "profileId",
    "profileDigest",
    "inputDigest",
    "factCardDigest",
    "resultDigest",
    "calibrationDigest",
    "rubricDigest",
    "reviewerRef",
  ]);
  for (const [k, n] of Object.entries(b)) {
    if (k === "calibrationDigest" && assistant) check(n === null);
    else ["key", "profileId", "reviewerRef"].includes(k) ? token(n) : hash(n);
  }
  return {
    version: assistant
      ? "explanation_assessment_v2"
      : "explanation_assessment_v1",
    binding: b as unknown as AssessmentBinding,
    method: v.method,
    ratings: parseRatings(v.ratings),
  };
}
export interface Calibration {
  version: "explanation_calibration_v1";
  method: "owner_local_v1" | "synthetic_fixture_v1";
  reviewerRef: string;
  rubricDigest: string;
  examplesDigest: string;
  completedAt: string;
  ratings: Ratings[];
  passed: boolean;
}
export function parseCalibration(value: unknown): Calibration {
  const v = fields(value, [
    "version",
    "method",
    "reviewerRef",
    "rubricDigest",
    "examplesDigest",
    "completedAt",
    "ratings",
    "passed",
  ]);
  check(v.version === "explanation_calibration_v1");
  member(v.method, ["owner_local_v1", "synthetic_fixture_v1"] as const);
  token(v.reviewerRef);
  hash(v.rubricDigest);
  hash(v.examplesDigest);
  timestamp(v.completedAt);
  array(v.ratings, 8, 8).forEach(parseRatings);
  check(typeof v.passed === "boolean");
  return structuredClone(v) as unknown as Calibration;
}
export async function assessmentMatches(
  value: unknown,
  expected: AssessmentBinding,
  live: boolean,
  assistant = false,
) {
  const assessment = parseAssessment(value);
  check(
    assessment.version ===
        (assistant
          ? "explanation_assessment_v2"
          : "explanation_assessment_v1") &&
      assessment.method ===
        (live
          ? assistant ? "assistant_local_v1" : "owner_local_v1"
          : "synthetic_fixture_v1"),
  );
  check(
    await fingerprintJson(assessment.binding) ===
      await fingerprintJson(expected),
  );
  return assessment;
}
