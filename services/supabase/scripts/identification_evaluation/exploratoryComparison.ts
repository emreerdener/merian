import { INPUT_GROUPS, type Profile } from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  improvementPercent,
  measurementSlice,
} from "./exploratoryMeasurement.ts";
import { validateReportInputs } from "./reports.ts";
import { MEASUREMENT_SCORER } from "./taxonomy.ts";
import { requireCondition as check } from "./validation.ts";

/** Separate from formal compare: incomplete cases remain visible and no qualification verdict is made. */
export async function compareExploratoryRuns(
  corpusValue: unknown,
  taxonomyValue: unknown,
  leftManifestValue: unknown,
  leftRecordsValue: unknown[],
  rightManifestValue: unknown,
  rightRecordsValue: unknown[],
  options: { leftProfile: Profile; rightProfile: Profile },
) {
  const left = await validateReportInputs(
    corpusValue,
    leftManifestValue,
    leftRecordsValue,
    taxonomyValue,
  );
  const right = await validateReportInputs(
    corpusValue,
    rightManifestValue,
    rightRecordsValue,
    taxonomyValue,
  );
  check(
    left.corpus.kind === "exploratory" && right.corpus.kind === "exploratory",
  );
  check(
    left.manifest.scorerVersion === MEASUREMENT_SCORER &&
      right.manifest.scorerVersion === MEASUREMENT_SCORER,
  );
  for (
    const key of [
      "boundary",
      "scorerVersion",
      "taxonomyVersion",
      "preparationVersion",
    ] as const
  ) check(left.manifest[key] === right.manifest[key]);
  for (
    const key of [
      "corpusDigest",
      "taxonomyDigest",
      "split",
      "stage",
      "mode",
      "repeats",
      "orderSeed",
    ] as const
  ) check(left.manifest.spec[key] === right.manifest.spec[key]);
  check(left.manifest.spec.repeats === 1);
  check(
    await fingerprintJson(left.manifest.source) ===
      await fingerprintJson(right.manifest.source),
  );
  check(
    await fingerprintJson(left.manifest.spec.caseIds.toSorted()) ===
      await fingerprintJson(right.manifest.spec.caseIds.toSorted()),
  );
  check(
    left.manifest.spec.profiles.includes(options.leftProfile) &&
      right.manifest.spec.profiles.includes(options.rightProfile),
  );
  const la = left.manifest.order.filter((a) =>
    a.profile === options.leftProfile
  );
  const ra = right.manifest.order.filter((a) =>
    a.profile === options.rightProfile
  );
  check(la.map((a) => a.caseId).join() === ra.map((a) => a.caseId).join());
  for (const a of la) {
    const b = ra.find((b) => b.caseId === a.caseId)!;
    check(a.inputDigest === b.inputDigest);
    if (options.leftProfile === options.rightProfile) {
      check(await fingerprintJson(a) === await fingerprintJson(b));
    }
  }
  const corpus = left.corpus;
  const slices = [...INPUT_GROUPS, "all_cases" as const].map((group) => {
    const baseline = measurementSlice(
      corpus,
      left.manifest,
      left.records,
      options.leftProfile,
      group,
    );
    const candidate = measurementSlice(
      corpus,
      right.manifest,
      right.records,
      options.rightProfile,
      group,
    );
    const latencyEligible = baseline.timing.latencyEligible &&
      candidate.timing.latencyEligible;
    // A same-provider candidate needs exactly the same reviewed rates. Across
    // providers the different pricing catalogs remain visible, with no cost verdict.
    const samePricing =
      left.manifest.spec.pricingDigest === right.manifest.spec.pricingDigest;
    const costEligible = samePricing &&
      baseline.cost.totalEstimatedUsd !== null &&
      candidate.cost.totalEstimatedUsd !== null;
    return {
      inputGroup: group,
      baseline,
      candidate,
      observedLatencyImprovementPercent: latencyEligible
        ? improvementPercent(
          baseline.timing.successfulIdentification.medianMs,
          candidate.timing.successfulIdentification.medianMs,
        )
        : null,
      observedCostImprovementPercent: costEligible
        ? improvementPercent(
          baseline.cost.totalEstimatedUsd,
          candidate.cost.totalEstimatedUsd,
        )
        : null,
      latencyMeasurementsComplete: latencyEligible,
      costMeasurementsComparable: costEligible,
      paired: baseline.cases.map((l) => {
        const r = candidate.cases.find((r) => r.caseId === l.caseId)!;
        return {
          caseId: l.caseId,
          left: l.assessment,
          right: r.assessment,
          providerMsChange: l.providerMs === null || r.providerMs === null
            ? null
            : r.providerMs - l.providerMs,
        };
      }),
    };
  });
  return {
    version: "identification_exploratory_comparison_v1",
    verdict: "measurement_only",
    baselineQualification: "not_independently_verified",
    screeningDecision: "not_evaluated",
    cacheComparability: "not_established",
    limitation: "experiment_controls_and_candidate_profiles_pending",
    corpusDigest: left.manifest.spec.corpusDigest,
    taxonomyDigest: left.manifest.spec.taxonomyDigest,
    scorerVersion: MEASUREMENT_SCORER,
    boundary: left.manifest.boundary,
    mode: left.manifest.spec.mode,
    source: left.manifest.source,
    left: {
      runId: left.manifest.spec.runId,
      runDigest: await fingerprintJson(left.manifest),
      profile: options.leftProfile,
      pricingDigest: left.manifest.spec.pricingDigest,
      assignments: la,
    },
    right: {
      runId: right.manifest.spec.runId,
      runDigest: await fingerprintJson(right.manifest),
      profile: options.rightProfile,
      pricingDigest: right.manifest.spec.pricingDigest,
      assignments: ra,
    },
    slices,
  };
}
