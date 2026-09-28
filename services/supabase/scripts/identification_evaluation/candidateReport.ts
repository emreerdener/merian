import type { compareExploratoryRuns } from "./exploratoryComparison.ts";
import type { ExplanationAssessment } from "./explanationContracts.ts";
import { ratingsPass } from "./explanationContracts.ts";
type Slice = Awaited<
  ReturnType<typeof compareExploratoryRuns>
>["slices"][number];
export type CandidateComparison = {
  slices: (
    & Pick<
      Slice,
      | "inputGroup"
      | "observedLatencyImprovementPercent"
      | "observedCostImprovementPercent"
    >
    & {
      baseline: Pick<Slice["baseline"], "scheduled">;
      candidate: Pick<Slice["candidate"], "scheduled">;
      paired: Pick<Slice["paired"][number], "left" | "right">[];
    }
  )[];
};
/** A fixed eight-case development screen, never production qualification. */
export function screenCandidate(
  c: CandidateComparison,
  assessments: Pick<ExplanationAssessment, "ratings">[],
  state: { live: boolean; complete: boolean; cache: boolean },
) {
  if (!state.live) return "synthetic_mechanics_only";
  if (!state.complete || !state.cache || assessments.length !== 16) {
    return "inconclusive";
  }
  if (assessments.some((a) => !ratingsPass(a.ratings))) return "inconclusive";
  const all = c.slices.find((s) => s.inputGroup === "all_cases")!;
  if (all.baseline.scheduled !== 8 || all.candidate.scheduled !== 8) {
    return "inconclusive";
  }
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
  ) {
    return "retain_baseline_quality_regression";
  }
  const unclear = (a: typeof all.paired[number]["left"]) =>
    ["no_result", "unverified"].includes(a.subject) ||
    ["no_result", "unverified", "ambiguous", "unmapped", "unresolved"].includes(
      a.identity,
    );
  if (all.paired.some((p) => unclear(p.left) || unclear(p.right))) {
    return "inconclusive";
  }
  const selected = c.slices.filter((s) =>
    ["photos", "description", "all_cases"].includes(s.inputGroup)
  );
  if (
    selected.some((s) =>
      s.observedLatencyImprovementPercent === null ||
      s.observedCostImprovementPercent === null
    )
  ) return "inconclusive";
  if (
    all.observedLatencyImprovementPercent! < 10 ||
    selected.some((s) =>
      s.observedLatencyImprovementPercent! < -10 ||
      s.observedCostImprovementPercent! < -10
    )
  ) return "retain_baseline_no_material_gain";
  return "candidate_for_further_qualification";
}
