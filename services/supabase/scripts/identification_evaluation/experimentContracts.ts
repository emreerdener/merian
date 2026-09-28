import { OPENAI_CANDIDATE_PROFILES } from "../../functions/_shared/ai/openaiRequest.ts";
import { parseReviewPlan, type ReviewPlan } from "./explanationContracts.ts";
/** Bounded, content-free plan for one photo/text development experiment. */
import {
  array,
  fields,
  id,
  integer,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";
import {
  CANDIDATE_SPEC_VERSION,
  type EvaluationPricing,
  hash,
  NULL_FIELDS_SPEC_VERSION,
  number,
  parseEvaluationPricing,
  PROVIDER_SPEC_VERSION,
  type SourceIdentity,
  timestamp,
  unique,
} from "./runContracts.ts";
import {
  executionProfile,
  NULL_FIELDS_PROFILES,
  type ReusableProfileId,
} from "./reusableProfiles.ts";

export const EXPERIMENT_METRICS = {
  latency: "successful_identification_arithmetic_median_v1",
  cost: "fixed_allocation_rate_aware_total_v1",
  improvementPercent: "100_times_baseline_minus_candidate_over_baseline",
  thresholdPercent: 10,
} as const;
export const NULL_FIELDS_PLAN_VERSION =
  "identification_experiment_plan_v4" as const;
export const NULL_FIELDS_METRICS = {
  ...EXPERIMENT_METRICS,
  thresholdPercent: null,
} as const;
export function hasAssistantReview(plan: Pick<ExperimentPlan, "version">) {
  return plan.version === "identification_experiment_plan_v3" ||
    plan.version === NULL_FIELDS_PLAN_VERSION;
}
export function experimentSpecVersion(
  plan: Pick<ExperimentPlan, "version" | "review">,
) {
  return plan.version === NULL_FIELDS_PLAN_VERSION
    ? NULL_FIELDS_SPEC_VERSION
    : plan.review
    ? CANDIDATE_SPEC_VERSION
    : PROVIDER_SPEC_VERSION;
}
export interface ExperimentPlan {
  version:
    | "identification_experiment_plan_v1"
    | "identification_experiment_plan_v2"
    | "identification_experiment_plan_v3"
    | typeof NULL_FIELDS_PLAN_VERSION;
  review?: ReviewPlan;
  experimentId: string;
  mode: "offline" | "live";
  reviewRef: string;
  source: SourceIdentity;
  corpusDigest: string;
  taxonomyDigest: string;
  preparationVersion: string;
  orderSeed: number;
  cases: { caseId: string; inputDigest: string }[];
  window: { startsAt: string; expiresAt: string };
  maxCalls: number;
  budgetUsd: number;
  metrics: typeof EXPERIMENT_METRICS | typeof NULL_FIELDS_METRICS;
  cacheControl:
    | "automatic_uncontrolled_no_extra_requests"
    | "explicit_no_breakpoints_v1";
  candidateDecision:
    | "deferred_cache_isolation_and_explanation_rubric"
    | "concise_explanation_latency_v1"
    | "concise_explanation_latency_ai_review_v1"
    | "null_fields_consistency_ai_review_v1";
  runs: {
    runId: string;
    profileId: ReusableProfileId;
    profileDigest: string;
    maxCalls: number;
    budgetUsd: number;
    pricing: EvaluationPricing;
    pricingDigest: string;
    readinessDigest: string | null;
  }[];
}
/** Integer nanodollars: ceil charges/reservations, floor budgets. */
export function chargeUnits(usd: number): number {
  number(usd, 0, 100000);
  return Math.ceil(usd * 1e9);
}
export function budgetUnits(usd: number): number {
  number(usd, 0, 100000);
  return Math.floor(usd * 1e9);
}

export function parseExperimentPlan(value: unknown): ExperimentPlan {
  const version = (value as { version?: unknown } | null)?.version;
  const nullFields = version === NULL_FIELDS_PLAN_VERSION;
  const assistant = nullFields ||
    version === "identification_experiment_plan_v3";
  const candidate = assistant ||
    (value as { version?: unknown } | null)?.version ===
      "identification_experiment_plan_v2";
  const v = fields(value, [
    ...(candidate ? ["review"] : []),
    "version",
    "experimentId",
    "mode",
    "reviewRef",
    "source",
    "corpusDigest",
    "taxonomyDigest",
    "preparationVersion",
    "orderSeed",
    "cases",
    "window",
    "maxCalls",
    "budgetUsd",
    "metrics",
    "cacheControl",
    "candidateDecision",
    "runs",
  ]);
  check(candidate || v.version === "identification_experiment_plan_v1");
  if (candidate) parseReviewPlan(v.review, assistant);
  token(v.experimentId);
  token(v.reviewRef);
  token(v.preparationVersion);
  member(v.mode, ["offline", "live"]);
  hash(v.corpusDigest);
  hash(v.taxonomyDigest);
  const source = fields(v.source, ["commit", "dirty", "digest", "sdk"]);
  check(
    typeof source.commit === "string" && /^[a-f0-9]{40}$/.test(source.commit),
  );
  check(typeof source.dirty === "boolean");
  hash(source.digest);
  check(
    typeof source.sdk === "string" &&
      /^npm:@google\/genai@\d+\.\d+\.\d+$/.test(source.sdk),
  );
  integer(v.orderSeed, 0, 0xffffffff);
  integer(v.maxCalls, 1, 32);
  number(v.budgetUsd, 0.000000001, 100000);
  const cases = array(v.cases, 1, 8).map((raw) => {
    const c = fields(raw, ["caseId", "inputDigest"]);
    id(c.caseId, "c");
    hash(c.inputDigest);
    return c;
  });
  unique(cases.map((c) => c.caseId));
  const window = fields(v.window, ["startsAt", "expiresAt"]);
  timestamp(window.startsAt);
  timestamp(window.expiresAt);
  check(
    Date.parse(window.expiresAt) > Date.parse(window.startsAt) &&
      Date.parse(window.expiresAt) - Date.parse(window.startsAt) <= 86400000,
  );
  const metrics = fields(v.metrics, Object.keys(EXPERIMENT_METRICS));
  const expectedMetrics = nullFields ? NULL_FIELDS_METRICS : EXPERIMENT_METRICS;
  check(Object.entries(expectedMetrics).every(([k, n]) => metrics[k] === n));
  check(
    v.cacheControl ===
        (candidate && !nullFields
          ? "explicit_no_breakpoints_v1"
          : "automatic_uncontrolled_no_extra_requests") &&
      v.candidateDecision ===
        (nullFields
          ? "null_fields_consistency_ai_review_v1"
          : assistant
          ? "concise_explanation_latency_ai_review_v1"
          : candidate
          ? "concise_explanation_latency_v1"
          : "deferred_cache_isolation_and_explanation_rubric"),
  );
  const runs = array(v.runs, 1, 4).map((raw) => {
    const r = fields(raw, [
      "runId",
      "profileId",
      "profileDigest",
      "maxCalls",
      "budgetUsd",
      "pricing",
      "pricingDigest",
      "readinessDigest",
    ]);
    token(r.runId);
    member(
      r.profileId,
      nullFields
        ? NULL_FIELDS_PROFILES
        : candidate
        ? OPENAI_CANDIDATE_PROFILES
        : ["gemini_photo_text_v1", "openai_photo_text_v1"] as const,
    );
    hash(r.profileDigest);
    hash(r.pricingDigest);
    integer(r.maxCalls, cases.length, cases.length);
    number(r.budgetUsd, 0.000000001, 100000);
    const pricing = parseEvaluationPricing(r.pricing);
    check(
      (pricing.version === "evaluation_openai_pricing_v1") ===
        (executionProfile(r.profileId) !== "gemini_pro"),
    );
    if (v.mode === "live") hash(r.readinessDigest);
    else check(r.readinessDigest === null);
    return { runId: r.runId, maxCalls: r.maxCalls, budgetUsd: r.budgetUsd };
  });
  if (candidate) {
    check(runs.length === 2 && v.maxCalls === cases.length * 2);
    const rawRuns = v.runs as Record<string, unknown>[];
    check(
      rawRuns.every((r, i) =>
        r.profileId ===
          (nullFields ? NULL_FIELDS_PROFILES : OPENAI_CANDIDATE_PROFILES)[i]
      ),
    );
    check(rawRuns[0].pricingDigest === rawRuns[1].pricingDigest);
    if (nullFields) check(cases.length <= 6);
    if (v.mode === "live") check(cases.length === (nullFields ? 6 : 8));
  }
  unique(runs.map((r) => r.runId));
  check(runs.reduce((n, r) => n + r.maxCalls, 0) <= v.maxCalls);
  check(
    runs.reduce((n, r) => n + budgetUnits(r.budgetUsd), 0) <=
      budgetUnits(v.budgetUsd),
  );
  return structuredClone(v) as unknown as ExperimentPlan;
}

export const EXPERIMENT_STOPS = [
  "uncertain_execution",
  "ledger_mismatch",
  "operational_failure",
  "model_mismatch",
  "usage_missing",
  "budget_exceeded",
  "call_limit",
  "window_expired",
  "run_stopped",
  "execution_interrupted",
  "configuration_changed",
  "cache_control_failed",
  "explanation_review_missing",
  "explanation_quality_failed",
] as const;
export type ExperimentStop = typeof EXPERIMENT_STOPS[number];

export function experimentGuard(
  plan: ExperimentPlan,
  runIndex: number,
  accounting: {
    calls: number;
    chargedUnits: number;
    runs: { calls: number; chargedUnits: number }[];
  },
  reservationUsd: number,
  now: number,
): ExperimentStop | null {
  const r = plan.runs[runIndex], spent = accounting.runs[runIndex];
  if (
    now < Date.parse(plan.window.startsAt) ||
    now >= Date.parse(plan.window.expiresAt)
  ) return "window_expired";
  if (accounting.calls >= plan.maxCalls || spent.calls >= r.maxCalls) {
    return "call_limit";
  }
  const reserve = chargeUnits(reservationUsd);
  if (
    accounting.chargedUnits + reserve > budgetUnits(plan.budgetUsd) ||
    spent.chargedUnits + reserve > budgetUnits(r.budgetUsd)
  ) return "budget_exceeded";
  return null;
}
