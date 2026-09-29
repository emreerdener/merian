/** Reference agreement and coverage, never population accuracy or routing authority. */
import { type Ratings, ratingsPass } from "./explanationContracts.ts";
import type { PhotoModelMeasurementRecord } from "./photoModelRecords.ts";
import type {
  SolRankAssignment,
  SolRankPacket,
} from "./solPhotoRankLivePreparation.ts";
import { SOL_RANK_PROFILE } from "./solPhotoRankCandidate.ts";
import { assessMeasuredReference } from "./scoring.ts";

export interface SolRankEntry {
  record: PhotoModelMeasurementRecord;
  ratings: Ratings;
}
export function solRankAssessment(
  packet: SolRankPacket,
  a: SolRankAssignment,
  e: Pick<SolRankEntry, "record">,
) {
  const reference = packet.corpus.cases.find((c) =>
    c.input.caseId === a.caseId
  )!.provisionalReference!;
  const review = packet.referenceReview.cases.find((c) =>
    c.caseId === a.caseId
  )!;
  const measured = assessMeasuredReference(
    reference,
    e.record.prediction,
    e.record.mapping,
  );
  return {
    ...measured,
    identityReferenceLimited: review.identitySupport === "limited_reference",
  };
}
/** Qualification of a provisional label comparison, separate from explanation ratings. */
export function solRankIdentityInterpretation(
  assessment: ReturnType<typeof solRankAssessment>,
) {
  if (assessment.subject === "no_result") return "no_result";
  if (assessment.subject === "unverified") return "unassessable_reference";
  if (assessment.subject === "disagreement") return "subject_disagreement";
  const identity = assessment.identity;
  if (["unmapped", "ambiguous"].includes(identity)) {
    return "unassessable_mapping";
  }
  if (identity === "unverified") return "unassessable_reference";
  if (identity === "no_result") return "no_result";
  if (identity === "agreement") return "reference_agreement";
  if (identity === "valid_abstention" || identity === "not_applicable") {
    return identity;
  }
  if (assessment.identityReferenceLimited) {
    return "unassessable_limited_reference";
  }
  if (identity === "unsupported_specificity") return "beyond_reviewed_rank";
  if (identity === "disagreement") return "reference_disagreement";
  return "unresolved";
}
export function solRankScreenDecision(
  packet: SolRankPacket,
  a: SolRankAssignment,
  e: SolRankEntry,
): "pass" | "failed" | "unassessable" {
  if (e.record.reason !== "completed") return "failed";
  const ratings = Object.values(e.ratings);
  if (ratings.some((r) => r.status === "fail")) return "failed";
  if (
    ratings.some((r) =>
      r.status !== "pass" &&
      !(r.status === "not_assessable" && r.reason === "insufficient_reference")
    )
  ) return "unassessable";
  const s = solRankAssessment(packet, a, e);
  if (s.subject !== "agreement") return "failed";
  if (["unmapped", "ambiguous", "unverified"].includes(s.identity)) {
    return "unassessable";
  }
  if (
    ["agreement", "valid_abstention", "not_applicable"].includes(s.identity)
  ) return "pass";
  // An uncertain source label cannot make a cautious broader name an established error.
  if (s.identityReferenceLimited) return "unassessable";
  return "failed";
}
export function solRankSummary(
  packet: SolRankPacket,
  entries: Map<number, SolRankEntry>,
  records: Map<number, PhotoModelMeasurementRecord>,
) {
  const attempts = packet.report.order.filter((a) => records.has(a.ordinal))
    .map((a) => {
      const e = entries.get(a.ordinal), record = records.get(a.ordinal)!;
      const assessment = solRankAssessment(packet, a, { record });
      return {
        ordinal: a.ordinal,
        caseId: a.caseId,
        phase: a.phase,
        profile: a.profile,
        reason: record.reason,
        mapping: record.mapping.status,
        assessment,
        identityInterpretation: solRankIdentityInterpretation(assessment),
        ratings: e?.ratings ?? null,
        explanationPassed: e ? ratingsPass(e.ratings) : false,
        providerMs: record.providerMs,
        normalizationMs: record.normalizationMs,
        estimatedUpperNanoUsd: record.estimatedUpperNanoUsd,
      };
    });
  const pairedIds = packet.plan.challengeCaseIds.filter((id) =>
    attempts.filter((a) =>
      a.phase === "challenge" && a.caseId === id && a.reason === "completed"
    ).length === 2
  );
  const median = (values: number[]) => {
    if (!values.length) return null;
    const sorted = [...values].sort((a, b) => a - b),
      half = Math.floor(sorted.length / 2);
    return sorted.length % 2
      ? sorted[half]
      : (sorted[half - 1] + sorted[half]) / 2;
  };
  return {
    version: "sol_photo_rank_summary_v2",
    evidenceStatus: packet.referenceReview.referenceStatus,
    independentTruthVerified: false,
    reusedDevelopmentCases: true,
    productionActivationAuthorized: false,
    confidenceCalibrationQualified: false,
    pairedChallengeCases: pairedIds.length,
    attempts,
    profiles: (["openai_photo_sol_low_v1", SOL_RANK_PROFILE] as const).flatMap((
      profile,
    ) =>
      (["screen", "challenge"] as const).map((phase) => {
        const selected = attempts.filter((a) =>
          a.profile === profile && a.phase === phase
        );
        const paired = selected.filter((a) =>
          a.phase === "challenge" && pairedIds.includes(a.caseId)
        );
        const counts = (key: "identity" | "subject") =>
          Object.fromEntries(
            [...new Set(selected.map((a) => a.assessment[key]))].map((
              category,
            ) => [
              category,
              selected.filter((a) => a.assessment[key] === category).length,
            ]),
          );
        return {
          profile,
          phase,
          attempts: selected.length,
          reviewedAttempts: selected.filter((a) => a.ratings !== null).length,
          subjectCounts: counts("subject"),
          // These are raw reference comparisons, not established model errors.
          identityCounts: counts("identity"),
          identityInterpretationCounts: Object.fromEntries(
            [...new Set(selected.map((a) => a.identityInterpretation))].map((
              category,
            ) => [
              category,
              selected.filter((a) => a.identityInterpretation === category)
                .length,
            ]),
          ),
          explanationPasses: selected.filter((a) => a.explanationPassed).length,
          explanationFailures: selected.filter((a) =>
            Object.values(a.ratings ?? {}).some((r) => r.status === "fail")
          ).length,
          referenceGapAttempts: selected.filter((a) =>
            Object.values(a.ratings ?? {}).some((r) =>
              r.reason === "insufficient_reference"
            )
          ).length,
          pairedTimingDenominator: paired.filter((a) =>
            a.providerMs !== null
          ).length,
          pairedProviderMedianMs: median(paired.flatMap((a) =>
            a.providerMs === null ? [] : [a.providerMs]
          )),
          knownCostAttempts: selected.filter((a) =>
            a.estimatedUpperNanoUsd !== null
          ).length,
          knownCostUpperUsd: selected.reduce((n, a) =>
            n + (a.estimatedUpperNanoUsd ?? 0), 0) / 1e9,
        };
      })
    ),
  };
}
