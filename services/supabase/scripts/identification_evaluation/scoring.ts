import {
  FLASH_DIAGNOSTIC_TRIGGER,
  FLASH_POSSIBLE,
  FLASH_STRONG,
  PRO_DIAGNOSTIC_TRIGGER,
  PRO_POSSIBLE,
  PRO_STRONG,
} from "../../functions/_shared/identify/thresholds.ts";
import {
  type EvaluationCase,
  INPUT_GROUPS,
  type InputGroup,
  OUTCOMES,
  type Prediction,
  type Profile,
  RANKS,
  type Rate,
  type ReferenceLabel,
  REPORT_VERSION,
  type Resolution,
  SCORER_VERSION,
  type ScoreReport,
  type Split,
  type Subject,
} from "./contracts.ts";
import { fingerprintCorpus } from "./evidence.ts";
import {
  parseEvaluationCorpus,
  parsePrediction,
  requireCondition,
} from "./validation.ts";

export function rate(numerator: number, denominator: number): Rate {
  requireCondition(
    Number.isSafeInteger(numerator) && Number.isSafeInteger(denominator) &&
      numerator >= 0 && numerator <= denominator,
  );
  return {
    numerator,
    denominator,
    value: denominator === 0 ? null : numerator / denominator,
    status: denominator === 0 ? "not_estimable" : "measured",
  };
}

export function assessDecision(testCase: EvaluationCase, result: Prediction) {
  return assessReference(testCase.reference, result);
}

/** Label comparison only. The caller owns whether the label is verified. */
export function assessReference(label: ReferenceLabel, result: Prediction) {
  const normalized = result.outcome === "normalized" ? result : null;
  const named = normalized?.subject === "biological" &&
    normalized.resolution === "named";
  const correct = named && label.resolution === "named" &&
    normalized.taxon !== null &&
    label.acceptableTaxa.some((taxon) =>
      taxon.id === normalized.taxon?.id && taxon.rank === normalized.taxon?.rank
    );
  const subjectCorrect = normalized?.subject === label.subject;
  const unresolvedExpected = label.resolution === "unresolved";
  return {
    named,
    correct,
    exactSpecies: correct && normalized?.taxon?.rank === "species",
    subjectCorrect,
    appropriateUnresolved: unresolvedExpected && subjectCorrect &&
      normalized?.resolution === "unresolved",
    falseBiological:
      (label.subject === "non_biological" || label.subject === "human") &&
      normalized?.subject === "biological",
    unsupportedBiological: label.subject === "indeterminate" &&
      normalized?.subject === "biological",
    unsupported: named &&
      (unresolvedExpected ||
        (normalized.taxon !== null && label.supportedRank !== null &&
          RANKS.indexOf(normalized.taxon.rank) >
            RANKS.indexOf(label.supportedRank))),
    unmapped: named && normalized.taxon === null,
    score: named ? normalized.confidence : null,
  };
}

function matrix<R extends string, C extends string>(
  rows: readonly R[],
  columns: readonly C[],
): Record<R, Record<C, number>> {
  return Object.fromEntries(
    rows.map((
      row,
    ) => [row, Object.fromEntries(columns.map((column) => [column, 0]))]),
  ) as Record<R, Record<C, number>>;
}

/** Pure point estimates over normalized fixtures; no runner or model invocation.
 * Each prediction is one predeclared case in one profile/split. Repeats cannot
 * be pooled here; duplicate IDs and unknown cases are rejected.
 */
export async function scoreEvaluation(
  corpusValue: unknown,
  predictionValues: readonly unknown[],
  scope: {
    profile: Profile;
    split: Split;
    inputGroup?: InputGroup;
    caseIds?: readonly string[];
  },
): Promise<ScoreReport> {
  const corpus = parseEvaluationCorpus(corpusValue);
  requireCondition(
    scope.profile === "gemini_flash_free" || scope.profile === "gemini_pro",
  );
  requireCondition(scope.split === "development" || scope.split === "held_out");
  requireCondition(
    scope.inputGroup === undefined || INPUT_GROUPS.includes(scope.inputGroup),
  );
  requireCondition(
    Array.isArray(predictionValues) &&
      predictionValues.length <= corpus.cases.length,
  );
  if (scope.caseIds !== undefined) {
    requireCondition(
      Array.isArray(scope.caseIds) && scope.caseIds.length > 0 &&
        new Set(scope.caseIds).size === scope.caseIds.length,
    );
    requireCondition(
      scope.caseIds.every((id) =>
        corpus.cases.some((c) =>
          c.input.caseId === id && c.input.split === scope.split
        )
      ),
    );
  }
  const scheduled = corpus.cases.filter((item) =>
    item.input.split === scope.split &&
    (scope.caseIds === undefined || scope.caseIds.includes(item.input.caseId))
  );
  const scheduledIds = new Set(scheduled.map((item) => item.input.caseId));
  const predictions = new Map<string, Prediction>();
  for (const value of predictionValues) {
    const prediction = parsePrediction(value);
    requireCondition(scheduledIds.has(prediction.caseId), "unknown_case");
    requireCondition(
      !predictions.has(prediction.caseId),
      "duplicate_prediction",
    );
    predictions.set(prediction.caseId, prediction);
  }
  const rows = scheduled.filter((item) =>
    scope.inputGroup === undefined || item.input.inputGroup === scope.inputGroup
  ).map((testCase) => {
    const result = predictions.get(testCase.input.caseId) ??
      { caseId: testCase.input.caseId, outcome: "unattempted" as const };
    return { testCase, result, assessment: assessDecision(testCase, result) };
  });
  const count = (test: (row: typeof rows[number]) => boolean) =>
    rows.filter(test).length;
  const biological = count((row) =>
    row.testCase.reference.subject === "biological"
  );
  const species = count((row) =>
    row.testCase.reference.supportedRank === "species"
  );
  const named = count((row) => row.assessment.named);
  const correct = count((row) => row.assessment.correct);
  const pro = scope.profile === "gemini_pro";
  const possible = pro ? PRO_POSSIBLE : FLASH_POSSIBLE;
  const strong = pro ? PRO_STRONG : FLASH_STRONG;
  const diagnostic = pro ? PRO_DIAGNOSTIC_TRIGGER : FLASH_DIAGNOSTIC_TRIGGER;
  const strongRows = rows.filter((row) =>
    row.assessment.score !== null && row.assessment.score >= strong
  );
  const diagnosticRows = rows.filter((row) =>
    row.assessment.score !== null && row.assessment.score >= diagnostic
  );
  const strongErrors =
    strongRows.filter((row) => !row.assessment.correct).length;
  const diagnosticErrors =
    diagnosticRows.filter((row) => !row.assessment.correct).length;
  const outcomes = Object.fromEntries(
    OUTCOMES.map((outcome) => [
      outcome,
      count((row) => row.result.outcome === outcome),
    ]),
  ) as Record<typeof OUTCOMES[number], number>;
  const subjects: Subject[] = [
    "biological",
    "non_biological",
    "indeterminate",
    "human",
  ];
  const resolutions: Resolution[] = ["named", "unresolved"];
  const subjectMatrix = matrix(subjects, [...subjects, "no_result"]);
  const resolutionMatrix = matrix(resolutions, [...resolutions, "no_result"]);
  for (const { testCase, result } of rows) {
    subjectMatrix[testCase.reference.subject][
      result.outcome === "normalized" ? result.subject : "no_result"
    ]++;
    resolutionMatrix[testCase.reference.resolution][
      result.outcome === "normalized" ? result.resolution : "no_result"
    ]++;
  }
  const bin = (min: number, max: number) => {
    const members = rows.filter((row) =>
      row.assessment.score !== null && row.assessment.score >= min &&
      row.assessment.score < max
    );
    return {
      correctness: rate(
        members.filter((row) => row.assessment.correct).length,
        members.length,
      ),
      meanScore: members.length === 0
        ? null
        : members.reduce((sum, row) => sum + row.assessment.score!, 0) /
          members.length,
    };
  };
  return {
    version: REPORT_VERSION,
    scorerVersion: SCORER_VERSION,
    evidenceKind: corpus.kind,
    corpusId: corpus.id,
    corpusDigest: await fingerprintCorpus(corpus),
    taxonomyVersion: corpus.taxonomyVersion,
    preparationVersion: corpus.preparationVersion,
    profile: scope.profile,
    split: scope.split,
    inputGroup: scope.inputGroup ?? "all_cases",
    verdict: "measurement_only",
    completeness: outcomes.unattempted > 0 || rows.length === 0
      ? "incomplete"
      : "complete",
    counts: {
      scheduled: rows.length,
      biological,
      speciesAnswerable: species,
      named,
      unsupportedSpecificity: count((row) => row.assessment.unsupported),
      unresolvedMapping: count((row) => row.assessment.unmapped),
    },
    outcomes,
    metrics: {
      exactSpecies: rate(
        count((row) =>
          row.testCase.reference.supportedRank === "species" &&
          row.assessment.exactSpecies
        ),
        species,
      ),
      offeredPrecision: rate(correct, named),
      answerCoverage: rate(
        count((row) =>
          row.testCase.reference.subject === "biological" &&
          row.assessment.named
        ),
        biological,
      ),
      correctAnswerYield: rate(correct, biological),
      subjectAccuracy: rate(
        count((row) => row.assessment.subjectCorrect),
        rows.length,
      ),
      appropriateUnresolved: rate(
        count((row) => row.assessment.appropriateUnresolved),
        count((row) => row.testCase.reference.resolution === "unresolved"),
      ),
      falseBiologicalAssertions: rate(
        count((row) => row.assessment.falseBiological),
        count((row) =>
          row.testCase.reference.subject === "non_biological" ||
          row.testCase.reference.subject === "human"
        ),
      ),
      unsupportedBiologicalAssertions: rate(
        count((row) => row.assessment.unsupportedBiological),
        count((row) => row.testCase.reference.subject === "indeterminate"),
      ),
      strongErrorRate: rate(strongErrors, rows.length),
      strongErrorAmongNamed: rate(strongErrors, strongRows.length),
      diagnosticErrorRate: rate(diagnosticErrors, rows.length),
      diagnosticErrorAmongNamed: rate(diagnosticErrors, diagnosticRows.length),
    },
    reliability: {
      below_possible: bin(0, possible),
      possible: bin(possible, strong),
      strong: bin(strong, Infinity),
      diagnostic_subset: bin(diagnostic, Infinity),
    },
    subjectMatrix,
    resolutionMatrix,
    performance: "not_measured",
    intervals: "not_computed",
  };
}
