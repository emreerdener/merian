/** Scheduled-case development hurdle. Never a confidence or superiority claim. */
import type { ReferenceLabel } from "./contracts.ts";
import {
  type ConfidenceObservation,
  parseConfidenceObservation,
} from "./confidenceScoring.ts";
import { assessReference } from "./scoring.ts";
import { parseFeatureReviewReceipt } from "./photoFeatureInstrument.ts";
import {
  integer,
  requireCondition as check,
  token,
  validateReference,
} from "./validation.ts";
export interface FeatureScoringCase {
  caseId: string;
  reference: ReferenceLabel;
  mechanisms: number[];
}
export interface FeatureScoringResult {
  arm: "primary" | "features";
  observation: ConfidenceObservation;
  review: unknown | null;
}
export function scorePhotoFeatures(
  cases: readonly FeatureScoringCase[],
  values: readonly FeatureScoringResult[],
) {
  check(cases.length === 18 && new Set(cases.map((c) => c.caseId)).size === 18);
  for (const c of cases) {
    token(c.caseId);
    validateReference(c.reference, false);
    check(
      c.mechanisms.length <= 3 &&
        new Set(c.mechanisms).size === c.mechanisms.length,
    );
    c.mechanisms.forEach((m) => integer(m, 1, 3));
  }
  const records = new Map<string, FeatureScoringResult>();
  for (const r of values) {
    check(r.arm === "primary" || r.arm === "features");
    const observation = parseConfidenceObservation(r.observation),
      id = observation.prediction.caseId;
    check(cases.some((c) => c.caseId === id));
    const key = `${id}-${r.arm}`;
    check(!records.has(key));
    check(r.arm !== "primary" || r.review === null);
    records.set(key, {
      arm: r.arm,
      observation,
      review: r.review === null ? null : parseFeatureReviewReceipt(r.review),
    });
  }
  const rows = cases.map((c) => {
    const assess = (arm: "primary" | "features") => {
      const record = records.get(`${c.caseId}-${arm}`);
      const prediction = record?.observation.prediction ??
        { caseId: c.caseId, outcome: "unattempted" as const };
      const a = assessReference(c.reference, prediction);
      return {
        prediction,
        assessment: a,
        success: (a.correct && !a.unsupported) || a.appropriateUnresolved,
        review: record?.review
          ? parseFeatureReviewReceipt(record.review)
          : null,
      };
    };
    return { c, primary: assess("primary"), features: assess("features") };
  });
  const wins = rows.filter((r) => r.features.success && !r.primary.success);
  const losses = rows.filter((r) => !r.features.success && r.primary.success);
  const reviewedWins = wins.filter((r) => {
    const review = r.features.review;
    if (!review?.eligible) return false;
    return review.verdicts[0].some((v, i) =>
      r.c.reference.resolution === "named"
        ? v.diagnosticValue === "distinguishing"
        : v.diagnosticValue === "shared" ||
          review.traits[i].visibility !== "visible"
    );
  });
  const limitedWins = reviewedWins.filter((r) =>
    r.c.reference.subject === "biological" &&
    r.c.reference.supportedRank !== "species" && r.c.mechanisms.length > 0
  );
  const mechanisms = [...new Set(limitedWins.flatMap((r) => r.c.mechanisms))]
    .sort();
  const unresolvedGains =
    reviewedWins.filter((r) =>
      r.c.reference.subject === "biological" &&
      r.c.reference.resolution === "unresolved"
    ).length;
  const nonmappingGain = reviewedWins.some((r) =>
    r.primary.prediction.outcome === "normalized" &&
    !r.primary.assessment.unmapped
  );
  const allValid = rows.every((r) =>
    r.primary.prediction.outcome === "normalized" &&
    r.features.prediction.outcome === "normalized" && r.features.review !== null
  );
  const newSubjectErrors =
    rows.filter((r) =>
      r.primary.assessment.subjectCorrect &&
      !r.features.assessment.subjectCorrect
    ).length;
  const hurdle = allValid && wins.length === reviewedWins.length &&
    limitedWins.length >= 3 && mechanisms.length >= 2 &&
    reviewedWins.length - losses.length >= 3 && unresolvedGains >= 1 &&
    losses.length === 0 && newSubjectErrors === 0 && nonmappingGain;
  return {
    version: "photo_feature_scores_v1",
    scheduled: 36,
    recorded: records.size,
    allValid,
    supported: {
      primary: rows.filter((r) => r.primary.success).length,
      features: rows.filter((r) => r.features.success).length,
    },
    wins: wins.map((r) => r.c.caseId),
    reviewedWins: reviewedWins.map((r) => r.c.caseId),
    losses: losses.map((r) => r.c.caseId),
    limitedWins: limitedWins.length,
    mechanisms,
    unresolvedGains,
    newSubjectErrors,
    nonmappingGain,
    outcomeHurdleMet: hurdle,
    advancementAuthorized: false,
    superiorityEstablished: false,
    confidenceQualification: false,
  };
}
