/** Six-photo consistency screen. No latency/cost win or production qualification. */
import type { CandidateComparison } from "./candidateReport.ts";
import {
  type ExplanationAssessment,
  ratingsPass,
} from "./explanationContracts.ts";

export function screenNullFieldsCandidate(
  comparison: CandidateComparison,
  assessments: Pick<ExplanationAssessment, "ratings">[],
  state: { live: boolean; complete: boolean },
) {
  if (!state.live) return "synthetic_mechanics_only";
  if (
    !state.complete || assessments.length !== 12 ||
    assessments.some((a) => !ratingsPass(a.ratings))
  ) return "inconclusive";
  const all = comparison.slices.find((s) => s.inputGroup === "all_cases");
  if (
    !all || all.baseline.scheduled !== 6 || all.candidate.scheduled !== 6 ||
    all.paired.length !== 6
  ) return "inconclusive";
  const faults = (a: typeof all.paired[number]["left"]) => [
    a.subject === "disagreement",
    a.identity === "disagreement",
    a.identity === "unsupported_specificity",
    a.falseBiological,
    a.unsupportedBiological,
    a.unsupportedSpecificity,
  ];
  if (
    all.paired.some((p) =>
      faults(p.right).some((bad, i) => bad && !faults(p.left)[i])
    )
  ) return "retain_baseline_quality_regression";
  const supported = (a: typeof all.paired[number]["left"]) =>
    a.subject === "agreement" &&
    ["agreement", "valid_abstention", "not_applicable"].includes(a.identity) &&
    !faults(a).some(Boolean);
  if (all.paired.some((p) => !supported(p.left) || !supported(p.right))) {
    return "inconclusive";
  }
  return "no_observed_regression_in_six_photo_screen";
}
