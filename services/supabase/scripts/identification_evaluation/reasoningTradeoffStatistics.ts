import type { ConfidenceObservation } from "./confidenceScoring.ts";
import {
  decisionMetrics,
  decisionRows,
  pairedDecision,
} from "./photoDecisionStatistics.ts";
import {
  TRADEOFF,
  TRADEOFF_ARMS,
  type TradeoffArm,
  type TradeoffCase,
} from "./reasoningTradeoffPreparation.ts";
import { requireCondition as check } from "./validation.ts";

export interface TradeoffResult {
  arm: TradeoffArm;
  observation: ConfidenceObservation;
  providerDurationMs: number;
}
export function tradeoffStatistics(
  cases: readonly TradeoffCase[],
  results: readonly TradeoffResult[],
) {
  check(
    cases.length === TRADEOFF.cases &&
      cases.filter((c) => c.stratum === "library").length ===
        TRADEOFF.libraryCases,
  );
  check(
    results.every((r) =>
      TRADEOFF_ARMS.includes(r.arm) && Number.isFinite(r.providerDurationMs) &&
      r.providerDurationMs >= 0
    ),
  );
  const rows = (arm: TradeoffArm, stratum?: "library" | "control") => {
    const subset = cases.filter((c) => !stratum || c.stratum === stratum);
    return decisionRows(
      subset,
      results.filter((r) =>
        r.arm === arm &&
        subset.some((c) => c.input.caseId === r.observation.prediction.caseId)
      ).map((r) => r.observation),
    );
  };
  // Validate all IDs and duplicates before any stratum filtering.
  for (const arm of TRADEOFF_ARMS) {
    decisionRows(
      cases,
      results.filter((r) => r.arm === arm).map((r) => r.observation),
    );
  }
  const timings = (arm: TradeoffArm) => {
    const values = results.filter((r) => r.arm === arm).map((r) =>
      r.providerDurationMs
    ).sort((a, b) => a - b);
    return {
      count: values.length,
      mean: values.length
        ? values.reduce((a, b) => a + b, 0) / values.length
        : null,
      median: values.length
        ? (values[Math.floor((values.length - 1) / 2)] +
          values[Math.ceil((values.length - 1) / 2)]) / 2
        : null,
      p90: values.length ? values[Math.ceil(values.length * 0.9) - 1] : null,
    };
  };
  const low = rows("low"), medium = rows("medium"), gemini = rows("gemini");
  const gainIndices = medium.flatMap((r, i) =>
    r.success && !low[i].success ? [i] : []
  );
  const losses = low.filter((r, i) => r.success && !medium[i].success).length;
  const biologicalGains =
    gainIndices.filter((i) =>
      low[i].prediction.outcome === "normalized" && !low[i].assessment.unmapped
    ).length;
  const libraryGains =
    gainIndices.filter((i) => cases[i].stratum === "library").length;
  const diagnostics = (arm: TradeoffArm, stratum: "library" | "control") => {
    const r = rows(arm, stratum);
    return {
      supported: r.filter((x) => x.success).length,
      unsupportedSpecificity: r.filter((x) => x.assessment.unsupported).length,
      falseAbstention: r.filter((x) =>
        x.c.reference.resolution === "named" &&
        x.prediction.outcome === "normalized" &&
        x.prediction.resolution === "unresolved"
      ).length,
      subjectErrors:
        r.filter((x) =>
          x.prediction.outcome === "normalized" && !x.assessment.subjectCorrect
        ).length,
    };
  };
  const strata = (["library", "control"] as const).map((s) => {
    const a = diagnostics("low", s),
      b = diagnostics("medium", s),
      g = diagnostics("gemini", s);
    return {
      stratum: s,
      low: a,
      medium: b,
      gemini: g,
      passes: b.supported >= g.supported &&
        b.unsupportedSpecificity <= a.unsupportedSpecificity &&
        b.falseAbstention <= a.falseAbstention &&
        b.subjectErrors <= a.subjectErrors,
    };
  });
  const latency = {
    low: timings("low"),
    medium: timings("medium"),
    gemini: timings("gemini"),
  };
  const mt = latency.medium, gt = latency.gemini;
  const complete = TRADEOFF_ARMS.every((a) =>
    rows(a).every((r) => r.prediction.outcome !== "unattempted")
  );
  const noTechnicalFailures = TRADEOFF_ARMS.every((a) =>
    rows(a).every((r) => r.prediction.outcome === "normalized")
  );
  const noMediumFailures = medium.every((r) =>
    r.prediction.outcome === "normalized"
  );
  const latencyPass = mt.count === TRADEOFF.cases &&
    gt.count === TRADEOFF.cases &&
    mt.mean !== null && gt.mean !== null && gt.mean > 0 &&
    mt.mean <= TRADEOFF.maximumLatencyRatio * gt.mean &&
    mt.median !== null && gt.median !== null && gt.median > 0 &&
    mt.median <= TRADEOFF.maximumLatencyRatio * gt.median &&
    mt.p90 !== null && gt.p90 !== null && mt.p90 <= gt.p90;
  const gates = {
    complete,
    netGain: gainIndices.length - losses >= TRADEOFF.minimumNetGain,
    libraryGain: libraryGains >= TRADEOFF.minimumLibraryGain,
    biologicalGain: biologicalGains >= 1,
    noLowRegressions: losses === 0,
    strata: strata.every((s) => s.passes),
    noMediumFailures,
    noTechnicalFailures,
    latency: latencyPass,
  };
  const paired = (control: typeof low) => {
    const { superiority: _unused, ...descriptive } = pairedDecision(
      control.map((r) => r.success),
      medium.map((r) => r.success),
    );
    return { ...descriptive, confirmatory: false };
  };
  return {
    complete,
    gates,
    advancesToFreshValidation: Object.values(gates).every(Boolean),
    gains: gainIndices.length,
    losses,
    biologicalGains,
    libraryGains,
    strata,
    latency,
    arms: Object.fromEntries(
      TRADEOFF_ARMS.map((
        arm,
      ) => [
        arm,
        decisionMetrics(
          cases,
          results.filter((r) => r.arm === arm).map((r) => r.observation),
        ),
      ]),
    ),
    comparisons: { mediumVsLow: paired(low), mediumVsGemini: paired(gemini) },
    productionQualification: false,
    confidenceQualification: false,
  };
}
