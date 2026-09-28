import { screenCandidate } from "./candidateReport.ts";
import { screenNullFieldsCandidate } from "./nullFieldsReport.ts";
import {
  hasAssistantReview,
  NULL_FIELDS_PLAN_VERSION,
} from "./experimentContracts.ts";
import { join } from "node:path";
import { experimentReportSnapshot } from "./experiment.ts";
import { compareExploratoryRuns } from "./exploratoryComparison.ts";
import { generateExploratoryReport } from "./exploratoryReport.ts";
import { improvementPercent } from "./exploratoryMeasurement.ts";
import { atomicJson } from "./files.ts";

/** Completed accounting is distinct from model qualification or a causal saving. */
export async function saveExperimentReport(root: string) {
  const snapshot = await experimentReportSnapshot(root);
  const { plan, digest, accounting, runs } = snapshot;
  const complete = accounting.stop === null &&
    accounting.completedRunIds.length === plan.runs.length;
  const reviewed = !!plan.review;
  const assistant = hasAssistantReview(plan);
  const nullFields = plan.version === NULL_FIELDS_PLAN_VERSION;
  const cacheValid = reviewed && complete &&
    plan.cacheControl === "explicit_no_breakpoints_v1" &&
    runs.every((r) =>
      r.records.every((a) =>
        a.usage?.cachedTokens === 0 && a.usage?.cacheWriteTokens === 0
      )
    );
  const reports = await Promise.all(
    runs.map(async (run, i) => ({
      runId: plan.runs[i].runId,
      profileId: plan.runs[i].profileId,
      profileDigest: plan.runs[i].profileDigest,
      measurement: await generateExploratoryReport(
        run.corpus,
        run.manifest,
        run.records,
        run.taxonomy,
      ),
    })),
  );
  const comparisons = [];
  for (let right = 1; right < runs.length; right++) {
    const left = runs[0], r = runs[right];
    const comparison = await compareExploratoryRuns(
      left.corpus,
      left.taxonomy,
      left.manifest,
      left.records,
      r.manifest,
      r.records,
      {
        leftProfile: left.manifest.spec.profiles[0],
        rightProfile: r.manifest.spec.profiles[0],
      },
    );
    comparisons.push({
      ...comparison,
      limitation: nullFields
        ? "ai_reviewed_six_photo_consistency_screen_uncontrolled_cache"
        : assistant
        ? "ai_reviewed_uncached_eight_case_development_screen_only"
        : reviewed
        ? "uncached_eight_case_development_screen_only"
        : "cache_isolation_and_candidate_selection_pending",
      pricingBasis: "frozen_experiment_rate_cards",
      baselineRunId: plan.runs[0].runId,
      comparatorRunId: plan.runs[right].runId,
      slices: comparison.slices.map((slice) => {
        const costEligible = complete && (!reviewed || cacheValid) &&
          slice.costMeasurementsComparable &&
          slice.baseline.cost.totalEstimatedUsd !== null &&
          slice.candidate.cost.totalEstimatedUsd !== null;
        return {
          ...slice,
          latencyMeasurementsComplete: slice.latencyMeasurementsComplete &&
            (nullFields ? complete : !reviewed || cacheValid),
          observedLatencyImprovementPercent: (!reviewed || cacheValid)
            ? slice.observedLatencyImprovementPercent
            : null,
          costMeasurementsComparable: costEligible,
          observedCostImprovementPercent: costEligible
            ? improvementPercent(
              slice.baseline.cost.totalEstimatedUsd,
              slice.candidate.cost.totalEstimatedUsd,
            )
            : null,
        };
      }),
    });
  }
  const report = {
    version: nullFields
      ? "identification_experiment_report_v4"
      : assistant
      ? "identification_experiment_report_v3"
      : reviewed
      ? "identification_experiment_report_v2"
      : "identification_experiment_report_v1",
    ...(reviewed
      ? { explanationAssessments: snapshot.assessments, review: plan.review }
      : {}),
    ...(assistant
      ? {
        explanationReview: {
          method: plan.mode === "live"
            ? "assistant_local_v1"
            : "synthetic_fixture_v1",
          independentHumanValidation: false,
          additionalJudgeCalls: 0,
          limitation: "ai_assessment_can_share_model_errors",
        },
      }
      : {}),
    planDigest: digest,
    evidenceStatus: plan.mode === "offline"
      ? "synthetic_mechanics_only"
      : assistant
      ? "ai_reviewed_development_screen"
      : "provisional_measurement_only",
    complete,
    accounting,
    metrics: plan.metrics,
    ...(nullFields
      ? {
        performanceInterpretation: "descriptive_only_uncontrolled_cache",
        promptConsistency: "four_null_field_wording_edits_only",
      }
      : {}),
    cacheComparability: reviewed && !nullFields
      ? cacheValid ? "verified_zero_reads_and_writes" : "inconclusive"
      : "not_established",
    screeningDecision: nullFields
      ? screenNullFieldsCandidate(
        comparisons[0],
        snapshot.assessments.map((a) => a.record),
        { live: plan.mode === "live", complete },
      )
      : reviewed
      ? screenCandidate(
        comparisons[0],
        snapshot.assessments.map((a) => a.record),
        { live: plan.mode === "live", complete, cache: cacheValid },
      )
      : "deferred_no_candidate",
    productionQualified: false,
    runs: reports,
    comparisons,
  };
  await atomicJson(join(root, "experiment-report.json"), report);
  return report;
}
