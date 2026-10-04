/** Frozen paired analysis. Observation pairs, never calls, are statistical units. */
import {
  type ConfidenceObservation,
  confidenceRows,
  confidenceSplitReport,
  type ScoringCase,
} from "./confidenceScoring.ts";
import type { ConfidenceCase } from "./confidenceCorpus.ts";
import { confidenceRate } from "./confidenceProtocol.ts";
import { requireCondition as check } from "./validation.ts";

export const PHOTO_DECISION_PROTOCOL = Object.freeze({
  version: "photo_provider_decision_v1",
  maxAttempts: 360,
  budgetNanoUsd: 20_000_000_000,
  seed: 20261001,
  practicalDifference: 0.05,
  familyAlpha: 0.05,
  // Reserve two comparisons even if no candidate is selected; never recycle alpha.
  comparisons: 2,
  method: "paired_discordant_clopper_pearson_bonferroni_v1",
  primary: "supported_outcome_per_scheduled_observation",
  developmentRule:
    "net_gain_at_least_two_no_more_than_one_species_regression_nonmapping_gain",
  strongDiagnostic: 0.95,
});

export function decisionRows(
  cases: readonly ScoringCase[],
  observations: readonly ConfidenceObservation[],
) {
  return confidenceRows(cases, observations).map((r) => ({
    ...r,
    success: (r.correct && r.assessment.subjectCorrect) ||
      r.assessment.appropriateUnresolved,
  }));
}
export function decisionMetrics(
  cases: readonly ScoringCase[],
  observations: readonly ConfidenceObservation[],
) {
  const rows = decisionRows(cases, observations);
  const primary = (members: typeof rows) =>
    confidenceRate(members.filter((r) => r.success).length, members.length);
  return {
    primary: primary(rows),
    byCategory: Object.fromEntries(
      [...new Set(cases.map((c) => c.category))].map((
        k,
      ) => [k, primary(rows.filter((r) => r.c.category === k))]),
    ),
    // Existing named metrics stay named; do not mistake them for the new primary.
    namedDiagnostics: confidenceSplitReport(rows, 0.95),
    correctNamedYield: confidenceRate(
      rows.filter((r) => r.correct && r.assessment.named).length,
      rows.filter((r) => r.c.reference.subject === "biological").length,
    ),
  };
}

function binomialCDF(k: number, n: number, p: number) {
  if (k < 0) return 0;
  if (k >= n || p === 0) return 1;
  if (p === 1) return 0;
  let term = (1 - p) ** n, sum = term;
  for (let i = 1; i <= k; i++) {
    term *= (n - i + 1) / i * p / (1 - p);
    sum += term;
  }
  return Math.min(1, sum);
}
/** Invert binomial tails. Tail level alpha/(4*m) gives simultaneous difference bounds. */
function interval(k: number, n: number, tail: number): [number, number] {
  function root(target: number, index: number) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 70; i++) {
      const mid = (lo + hi) / 2;
      if (binomialCDF(index, n, mid) > target) lo = mid;
      else hi = mid;
    }
    return (lo + hi) / 2;
  }
  return [k === 0 ? 0 : root(1 - tail, k - 1), k === n ? 1 : root(tail, k)];
}
export function pairedDecision(
  control: readonly boolean[],
  challenger: readonly boolean[],
) {
  check(
    control.length === challenger.length && control.length > 0 &&
      control.length <= 100,
  );
  const n = control.length;
  const wins = challenger.filter((x, i) => x && !control[i]).length;
  const losses = control.filter((x, i) => x && !challenger[i]).length;
  const discordant = wins + losses;
  const effect = (wins - losses) / n;
  const tail = PHOTO_DECISION_PROTOCOL.familyAlpha /
    (4 * PHOTO_DECISION_PROTOCOL.comparisons);
  const winCI = interval(wins, n, tail), lossCI = interval(losses, n, tail);
  const lower = winCI[0] - lossCI[1], upper = winCI[1] - lossCI[0];
  const p = discordant === 0
    ? 1
    : Math.min(1, 2 * binomialCDF(Math.min(wins, losses), discordant, 0.5));
  return {
    observations: n,
    bothCorrect: control.filter((x, i) => x && challenger[i]).length,
    bothIncorrect: control.filter((x, i) => !x && !challenger[i]).length,
    challengerOnlyCorrect: wins,
    controlOnlyCorrect: losses,
    effect,
    simultaneousPairedInterval: { lower, upper, familyCoverageAtLeast: 0.95 },
    exactMcNemarP: p,
    bonferroniP: Math.min(1, p * PHOTO_DECISION_PROTOCOL.comparisons),
    superiority: effect >= PHOTO_DECISION_PROTOCOL.practicalDifference &&
      lower > 0 &&
      p <=
        PHOTO_DECISION_PROTOCOL.familyAlpha /
          PHOTO_DECISION_PROTOCOL.comparisons,
  };
}

export function selectEvidenceCandidate(
  cases: readonly ConfidenceCase[],
  a: readonly ConfidenceObservation[],
  c: readonly ConfidenceObservation[],
) {
  check(
    cases.length === 20 && cases.every((x) => x.input.split === "development"),
  );
  const control = decisionRows(cases, a), candidate = decisionRows(cases, c);
  const complete = [...control, ...candidate].every((r) =>
    r.prediction.outcome !== "unattempted"
  );
  const gains = candidate.filter((r, i) => r.success && !control[i].success);
  const losses = control.filter((r, i) => r.success && !candidate[i].success);
  const nonmappingGains =
    candidate.filter((r, i) =>
      r.success && !control[i].success && !control[i].assessment.unmapped &&
      control[i].prediction.outcome === "normalized"
    ).length;
  const speciesRegressions =
    control.filter((r, i) =>
      r.c.reference.supportedRank === "species" && r.success &&
      !candidate[i].success
    ).length;
  return {
    selected: complete && gains.length - losses.length >= 2 &&
      nonmappingGains > 0 && speciesRegressions <= 1,
    complete,
    gains: gains.length,
    losses: losses.length,
    nonmappingGains,
    speciesRegressions,
  };
}
