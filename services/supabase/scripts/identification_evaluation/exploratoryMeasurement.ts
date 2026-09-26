import {
  INPUT_GROUPS,
  type InputGroup,
  OUTCOMES,
  type Profile,
} from "./contracts.ts";
import type { ExploratoryCorpus } from "./exploratory.ts";
import { fingerprintJson } from "./evidence.ts";
import { type RateAwareCost, rateAwareCost } from "./measurementCost.ts";
import type { AttemptRecord, RunManifest } from "./runContracts.ts";
import { assessMeasuredReference, rate } from "./scoring.ts";
import { requireCondition as check } from "./validation.ts";

/** Arithmetic median, intentionally distinct from legacy report nearest-rank p50. */
export function median(values: readonly number[]): number | null {
  check(values.every((n) => Number.isFinite(n) && n >= 0));
  const sorted = values.toSorted((a, b) => a - b), n = sorted.length;
  return n === 0
    ? null
    : n % 2
    ? sorted[(n - 1) / 2]
    : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}
export function improvementPercent(
  baseline: number | null,
  candidate: number | null,
): number | null {
  return baseline === null || baseline <= 0 || candidate === null
    ? null
    : 100 * (baseline - candidate) / baseline;
}
const timing = (values: (number | null)[], live: boolean) => {
  const known = values.filter((n): n is number =>
    n !== null && Number.isFinite(n) && n > 0
  );
  return {
    count: known.length,
    missingOrInvalid: values.length - known.length,
    medianMs: live ? median(known) : null,
    minimumMs: live && known.length ? Math.min(...known) : null,
    maximumMs: live && known.length ? Math.max(...known) : null,
  };
};
export function measurementSlice(
  corpus: ExploratoryCorpus,
  manifest: RunManifest,
  records: AttemptRecord[],
  profile: Profile,
  inputGroup: InputGroup | "all_cases",
) {
  const live = manifest.spec.mode === "live";
  const selected = corpus.cases.filter((c) =>
    manifest.spec.caseIds.includes(c.input.caseId) &&
    (inputGroup === "all_cases" || c.input.inputGroup === inputGroup)
  );
  const rows = selected.map((c) => {
    const assignment = manifest.order.find((a) =>
      a.profile === profile && a.caseId === c.input.caseId
    )!;
    check(assignment !== undefined);
    const record = records.find((r) => r.key === assignment.key)!;
    check(record !== undefined);
    let cost: RateAwareCost = rateAwareCost(
      live ? manifest.pricing : null,
      assignment.model,
      record.usage,
    );
    if (
      live &&
      (record.prediction.outcome === "unattempted" ||
        record.prediction.outcome === "unknown_execution" ||
        record.returnedModel !== assignment.model)
    ) {
      cost = {
        method: "rate_aware_usage_v1",
        status: "incomplete",
        usd: null,
        reason: record.prediction.outcome === "unattempted"
          ? "unattempted"
          : record.prediction.outcome === "unknown_execution"
          ? "unknown_execution"
          : "model_mismatch",
      };
    }
    return {
      caseId: c.input.caseId,
      inputGroup: c.input.inputGroup,
      record,
      assessment: assessMeasuredReference(
        c.provisionalReference,
        record.prediction,
        record.mapping ?? null,
      ),
      cost,
      hasReference: c.provisionalReference !== null,
    };
  });
  const normalized = rows.filter((r) =>
    r.record.prediction.outcome === "normalized"
  );
  const named = normalized.filter((r) =>
    r.record.prediction.outcome === "normalized" &&
    r.record.prediction.subject === "biological" &&
    r.record.prediction.resolution === "named"
  );
  const mapped = named.filter((r) => r.record.mapping?.status === "matched");
  const assessedIdentity = rows.filter((r) =>
    ["agreement", "disagreement", "unsupported_specificity"].includes(
      r.assessment.identity,
    )
  );
  const successful = timing(normalized.map((r) => r.record.providerMs), live);
  const costKnown = rows.filter((r) => r.cost.status === "complete");
  const knownUsd = costKnown.reduce((n, r) => n + r.cost.usd!, 0);
  const completeCost = live && rows.length > 0 &&
    costKnown.length === rows.length;
  const knownUpper = rows.filter((r) => r.record.estimatedUpperUsd !== null);
  return {
    profile,
    inputGroup,
    scheduled: rows.length,
    coverage: rows.length ? "covered" as const : "untested" as const,
    referenceCounts: {
      independentlyReviewed: 0,
      provisional: rows.filter((r) => r.hasReference).length,
      unverified: rows.filter((r) => !r.hasReference).length,
    },
    outcomes: Object.fromEntries(
      OUTCOMES.map((o) => [
        o,
        rows.filter((r) => r.record.prediction.outcome === o).length,
      ]),
    ),
    mapping: {
      named: named.length,
      matched: mapped.length,
      ambiguous:
        named.filter((r) => r.record.mapping?.status === "ambiguous").length,
      unmapped:
        named.filter((r) => r.record.mapping?.status === "unmapped").length,
      coverage: rate(mapped.length, named.length),
    },
    provisional: {
      subjectAgreement: rate(
        rows.filter((r) => r.assessment.subject === "agreement").length,
        rows.filter((r) => r.hasReference).length,
      ),
      subjectAssessmentCoverage: rate(
        rows.filter((r) =>
          r.hasReference && r.record.prediction.outcome === "normalized"
        ).length,
        rows.filter((r) => r.hasReference).length,
      ),
      offeredIdentityAgreement: rate(
        rows.filter((r) => r.assessment.identity === "agreement").length,
        assessedIdentity.length,
      ),
      identityAssessmentCoverage: rate(
        assessedIdentity.length,
        named.filter((r) => r.hasReference).length,
      ),
      identityDisagreements:
        rows.filter((r) => r.assessment.identity === "disagreement").length,
      unsupportedSpecificity:
        rows.filter((r) => r.assessment.unsupportedSpecificity).length,
      falseBiologicalAssertions:
        rows.filter((r) => r.assessment.falseBiological).length,
      unsupportedBiologicalAssertions:
        rows.filter((r) => r.assessment.unsupportedBiological).length,
      validAbstentions:
        rows.filter((r) => r.assessment.identity === "valid_abstention").length,
    },
    timing: {
      method: "successful_median_arithmetic_v1",
      successfulIdentification: successful,
      latencyEligible: live && rows.length > 0 &&
        normalized.length === rows.length && successful.count === rows.length &&
        rows.every((r) => r.record.reason === "completed"),
      completedProvider: timing(
        rows.filter((r) =>
          ["normalized", "refusal", "invalid_output"].includes(
            r.record.prediction.outcome,
          )
        ).map((r) => r.record.providerMs),
        live,
      ),
      failures: timing(
        rows.filter((r) =>
          r.record.prediction.outcome !== "normalized" &&
          r.record.prediction.outcome !== "unattempted"
        ).map((r) => r.record.providerMs),
        live,
      ),
      normalization: timing(
        normalized.map((r) => r.record.normalizationMs),
        live,
      ),
      missingProviderDurations:
        rows.filter((r) =>
          r.record.prediction.outcome !== "unattempted" &&
          r.record.providerMs === null
        ).length,
    },
    cost: {
      method: "rate_aware_usage_v1",
      currency: "USD",
      status: !live ? "not_measured" : completeCost ? "complete" : "incomplete",
      knownEstimatedUsd: live ? knownUsd : null,
      totalEstimatedUsd: completeCost ? knownUsd : null,
      knownAttempts: costKnown.length,
      incompleteAttempts: rows.length - costKnown.length,
      conservativeKnownUpperUsd: live
        ? knownUpper.reduce((n, r) => n + r.record.estimatedUpperUsd!, 0)
        : null,
      conservativeUnknownAttempts:
        rows.filter((r) =>
          r.record.prediction.outcome !== "unattempted" &&
          r.record.estimatedUpperUsd === null
        ).length,
      additionalOperations: "not_supported_by_current_profiles",
    },
    cases: rows.map(({ caseId, inputGroup, record, assessment, cost }) => ({
      caseId,
      inputGroup,
      outcome: record.prediction.outcome,
      reason: record.reason,
      prediction: record.prediction,
      mapping: record.mapping,
      candidateMappings: record.candidateMappings,
      assessment,
      providerMs: live ? record.providerMs : null,
      normalizationMs: live ? record.normalizationMs : null,
      rateAwareCost: cost,
    })),
  };
}

/** Inputs must first pass validateReportInputs; no raw prose or provider I/O. */
export async function measuredExploratoryReport(
  corpus: ExploratoryCorpus,
  manifest: RunManifest,
  records: AttemptRecord[],
) {
  return {
    version: "identification_exploratory_report_v2" as const,
    runId: manifest.spec.runId,
    runDigest: await fingerprintJson(manifest),
    corpusDigest: manifest.spec.corpusDigest,
    taxonomyDigest: manifest.spec.taxonomyDigest,
    scorerVersion: manifest.scorerVersion,
    boundary: manifest.boundary,
    mode: manifest.spec.mode,
    verdict: "measurement_only" as const,
    evidenceStatus: corpus.evidenceOrigin === "synthetic"
      ? "synthetic_mechanics_only"
      : "exploratory_provisional",
    baselineQualification: "not_independently_verified",
    explanationQuality: manifest.version === "identification_provider_run_v2"
      ? "assessment_recorded_in_experiment_report"
      : "not_measured_brevity_candidate_deferred",
    completeness:
      records.some((r) =>
          ["unattempted", "unknown_execution"].includes(r.prediction.outcome)
        )
        ? "incomplete"
        : "complete",
    referenceCounts: {
      independentlyReviewed: 0,
      provisional:
        corpus.cases.filter((c) => c.provisionalReference !== null).length,
      unverified:
        corpus.cases.filter((c) => c.provisionalReference === null).length,
    },
    approvedBudgetUsd: manifest.spec.budgetUsd,
    pricingDigest: manifest.spec.pricingDigest,
    scheduled: records.length,
    attempted:
      records.filter((r) => r.prediction.outcome !== "unattempted").length,
    slices: manifest.spec.profiles.flatMap((profile) =>
      [...INPUT_GROUPS, "all_cases" as const].map((group) =>
        measurementSlice(corpus, manifest, records, profile, group)
      )
    ),
  };
}
export type MeasuredExploratoryReport = Awaited<
  ReturnType<typeof measuredExploratoryReport>
>;
export function renderMeasuredReport(
  report: MeasuredExploratoryReport,
): string {
  const lines = [
    "# Exploratory identification measurement",
    "",
    `Run: ${report.runId}. Mode: ${report.mode}. Status: ${report.completeness}.`,
    "",
    "Provisional references only; this does not establish independently verified accuracy or qualify a provider. Unmapped identities are unassessed, not wrong answers. Offline timings/costs are not measured. Provider time excludes upload, persistence and app rendering. Cost uses reviewed rates, not an invoice.",
    "",
    "| Profile | Input | Cases | Mapped / named | Assessed identity agreement | Successful median ms | Full-allocation estimated USD |",
    "| --- | --- | ---: | --- | --- | --- | --- |",
  ];
  for (const s of report.slices) {
    const a = s.provisional.offeredIdentityAgreement;
    lines.push(
      `| ${s.profile} | ${s.inputGroup} | ${s.scheduled} | ${s.mapping.matched}/${s.mapping.named} | ${a.numerator}/${a.denominator} | ${
        s.timing.successfulIdentification.medianMs ?? "not measured"
      } | ${s.cost.totalEstimatedUsd ?? "unknown / not measured"} |`,
    );
  }
  lines.push(
    "",
    "See summary.json for every case, assessment denominators, ambiguity, unsupported specificity, failures, missing measurements and partial known costs. Partial medians are diagnostic; latency eligibility requires every scheduled case. Unknown cost is never treated as zero.",
    report.explanationQuality === "assessment_recorded_in_experiment_report"
      ? "Explanation ratings and completion are recorded separately in experiment-report.json. This per-run report does not establish explanation quality."
      : "Explanation quality is not measured.",
    "",
  );
  return lines.join("\n");
}
