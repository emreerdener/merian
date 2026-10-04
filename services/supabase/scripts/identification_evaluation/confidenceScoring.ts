import { OUTCOMES, type Prediction, RANKS } from "./contracts.ts";
import type { ConfidenceCase, ConfidenceCorpus } from "./confidenceCorpus.ts";
import {
  CONFIDENCE_PROTOCOL as P,
  confidenceRate as rate,
} from "./confidenceProtocol.ts";
import { assessReference } from "./scoring.ts";
import { type IdentityMapping, parseIdentityMapping } from "./taxonomy.ts";
import {
  fields,
  parsePrediction,
  requireCondition as check,
} from "./validation.ts";

export interface ConfidenceObservation {
  prediction: Prediction;
  mapping: IdentityMapping | null;
}
export function parseConfidenceObservation(
  value: unknown,
): ConfidenceObservation {
  const v = fields(value, ["prediction", "mapping"]);
  const prediction = parsePrediction(v.prediction);
  if (prediction.outcome !== "normalized") {
    check(v.mapping === null);
    return { prediction, mapping: null };
  }
  const named = prediction.subject === "biological" &&
    prediction.resolution === "named";
  const mapping = parseIdentityMapping(v.mapping, prediction.taxon);
  check(
    named
      ? mapping.status !== "not_applicable"
      : mapping.status === "not_applicable" && prediction.taxon === null,
  );
  return { prediction, mapping };
}
export type ScoringCase = Pick<
  ConfidenceCase,
  "input" | "reference" | "category" | "taxaGroup"
>;
export function confidenceRows(
  cases: readonly ScoringCase[],
  values: readonly ConfidenceObservation[],
) {
  const ids = new Set(cases.map((c) => c.input.caseId));
  check(ids.size === cases.length);
  const predictions = new Map<string, ConfidenceObservation>();
  for (const raw of values) {
    const value = parseConfidenceObservation(raw), id = value.prediction.caseId;
    check(ids.has(id), "unknown_case");
    check(!predictions.has(id), "duplicate_prediction");
    predictions.set(id, value);
  }
  return cases.map((c) => {
    const value = predictions.get(c.input.caseId) ?? {
      prediction: { caseId: c.input.caseId, outcome: "unattempted" as const },
      mapping: null,
    };
    const assessment = assessReference(c.reference, value.prediction);
    return {
      c,
      ...value,
      assessment,
      correct: assessment.correct && !assessment.unsupported,
    };
  });
}
type Rows = ReturnType<typeof confidenceRows>;
function strongRows(rows: Rows, cutoff: number) {
  return rows.filter((r) =>
    r.assessment.named && r.assessment.score !== null &&
    r.assessment.score >= cutoff
  );
}
function passes(rows: Rows, cutoff: number): boolean {
  const members = strongRows(rows, cutoff),
    correct = members.filter((r) => r.correct).length;
  // Integer comparison avoids floating-point rounding at exactly 95%.
  return members.length >= P.minimumStrongCount &&
    correct * 100 >= members.length * (P.minimumPrecision * 100);
}
export function selectConfidenceCutoff(rows: Rows): number | null {
  if (
    rows.length !== P.casesPerSplit ||
    rows.some((r) => r.prediction.outcome === "unattempted")
  ) return null;
  return P.cutoffs.find((t) => passes(rows, t)) ?? null;
}
function metrics(rows: Rows, cutoff: number) {
  const count = (fn: (r: Rows[number]) => boolean) => rows.filter(fn).length;
  const biological = count((r) => r.c.reference.subject === "biological");
  const named = rows.filter((r) => r.assessment.named),
    strong = strongRows(rows, cutoff);
  const abstentionEligible = rows.filter((r) =>
    r.c.reference.subject === "biological" &&
    r.c.reference.resolution === "unresolved"
  );
  const controls = rows.filter((r) =>
    r.c.reference.subject === "non_biological"
  );
  const rateOf = (r: Rows, fn: (v: Rows[number]) => boolean) =>
    rate(r.filter(fn).length, r.length);
  return {
    scheduled: rows.length,
    outcomes: Object.fromEntries(
      OUTCOMES.map((k) => [k, count((r) => r.prediction.outcome === k)]),
    ),
    namedPrecision: rateOf(named, (r) => r.correct),
    strongPrecision: rateOf(strong, (r) => r.correct),
    strongErrors: rateOf(strong, (r) => !r.correct),
    strongMappingFailures: rateOf(strong, (r) => r.assessment.unmapped),
    mappedStrongErrors: rateOf(
      strong,
      (r) => !r.correct && !r.assessment.unmapped,
    ),
    strongCoverage: rate(strong.length, rows.length),
    biologicalAnswerCoverage: rate(
      count((r) =>
        r.c.reference.subject === "biological" && r.assessment.named
      ),
      biological,
    ),
    correctAnswerYield: rate(
      count((r) => r.c.reference.subject === "biological" && r.correct),
      biological,
    ),
    subjectAccuracy: rateOf(rows, (r) => r.assessment.subjectCorrect),
    appropriateAbstentions: rateOf(
      abstentionEligible,
      (r) => r.assessment.appropriateUnresolved,
    ),
    missedAnswers: rateOf(
      rows.filter((r) => r.c.reference.resolution === "named"),
      (r) =>
        r.prediction.outcome === "normalized" &&
        r.prediction.resolution === "unresolved",
    ),
    falseBiologicalAssertions: rateOf(
      controls,
      (r) => r.assessment.falseBiological,
    ),
    unsupportedSpecificity: rateOf(named, (r) => r.assessment.unsupported),
    mappingFailures: rateOf(named, (r) => r.assessment.unmapped),
    mappedNamedErrors: rateOf(
      named,
      (r) => !r.correct && !r.assessment.unmapped,
    ),
    biologicalAbstentions: count((r) =>
      r.prediction.outcome === "normalized" &&
      r.prediction.subject === "biological" &&
      r.prediction.resolution === "unresolved"
    ),
    bins: P.bins.map((bin) => {
      const members = named.filter((r) =>
        r.assessment.score !== null &&
        r.assessment.score >= bin.min &&
        (r.assessment.score < bin.max ||
          bin.inclusiveMax && r.assessment.score === bin.max)
      );
      return {
        ...bin,
        correctness: rateOf(members, (r) => r.correct),
        meanScore: members.length
          ? members.reduce((n, r) => n + r.assessment.score!, 0) /
            members.length
          : null,
      };
    }),
  };
}
export function confidenceSplitReport(rows: Rows, cutoff: number) {
  check(P.cutoffs.includes(cutoff));
  const breakdown = (
    keys: readonly string[],
    key: (r: Rows[number]) => string,
  ) =>
    Object.fromEntries(
      keys.map((k) => [k, metrics(rows.filter((r) => key(r) === k), cutoff)]),
    );
  return {
    cutoff,
    ...metrics(rows, cutoff),
    categories: breakdown(P.categories, (r) => r.c.category),
    referenceRanks: breakdown(
      [...RANKS, "unresolved"],
      (r) => r.c.reference.supportedRank ?? "unresolved",
    ),
    returnedRanks: breakdown(
      [...RANKS, "unmapped", "ambiguous", "no_named_answer"],
      (r) =>
        r.assessment.named
          ? r.prediction.outcome === "normalized" && r.prediction.taxon
            ? r.prediction.taxon.rank
            : r.mapping?.status === "ambiguous"
            ? "ambiguous"
            : "unmapped"
          : "no_named_answer",
    ),
  };
}
export function confidenceAssessment(
  corpus: ConfidenceCorpus,
  observations: readonly ConfidenceObservation[],
  selectedCutoff: number | null,
) {
  check(selectedCutoff === null || P.cutoffs.includes(selectedCutoff));
  const rows = confidenceRows(corpus.cases, observations);
  const development = rows.filter((r) => r.c.input.split === "development");
  const validation = rows.filter((r) => r.c.input.split === "held_out");
  const complete = (r: Rows) =>
    r.length === P.casesPerSplit &&
    r.every((v) => v.prediction.outcome !== "unattempted");
  const developmentSelection = selectConfidenceCutoff(development);
  check(selectedCutoff === null || selectedCutoff === developmentSelection);
  const passed = corpus.referenceStatus === "valid" &&
    selectedCutoff !== null &&
    complete(development) && complete(validation) &&
    passes(validation, selectedCutoff);
  const reason = corpus.referenceStatus !== "valid"
    ? "reference_invalidated"
    : !complete(development)
    ? "development_incomplete"
    : developmentSelection === null
    ? "no_development_cutoff"
    : selectedCutoff === null
    ? "selection_not_frozen"
    : !complete(validation)
    ? "validation_incomplete"
    : passed
    ? "validation_passed"
    : "validation_failed";
  return {
    version: P.version,
    scorerVersion: P.scorerVersion,
    evidenceKind: corpus.kind,
    referenceReviewMethod: corpus.kind === "reference"
      ? P.referenceReviewMethod
      : "synthetic",
    independentHumanValidation: false,
    decision: reason,
    // Synthetic fixtures prove tooling, never authorize a real threshold.
    recommendedStrong: corpus.kind === "reference" && passed
      ? selectedCutoff
      : P.fallbackStrong,
    validationRulePassed: passed,
    possible: P.possible,
    selectedCutoff,
    selectionRequiredBeforeValidation: true,
    productionActivationAuthorized: false,
    probabilityCalibrationClaim: false,
    scope: "predeclared_diagnostic_mixture_only",
    development: confidenceSplitReport(
      development,
      selectedCutoff ?? P.fallbackStrong,
    ),
    validation: confidenceSplitReport(
      validation,
      selectedCutoff ?? P.fallbackStrong,
    ),
  };
}
