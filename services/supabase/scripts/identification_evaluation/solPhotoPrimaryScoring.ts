/** Reference agreement and coverage, never population accuracy or routing authority. */
import { type Ratings, ratingsPass } from "./explanationContracts.ts";
import type { SolPrimaryRecord } from "./solPhotoPrimaryRecords.ts";
import type {
  SolPrimaryAssignment,
  SolPrimaryPacket,
} from "./solPhotoPrimaryLivePreparation.ts";
import { SOL_PRIMARY_PROFILE } from "../../functions/_shared/ai/openaiSolPrimary.ts";
import { assessMeasuredReference } from "./scoring.ts";

export interface SolPrimaryEntry {
  record: SolPrimaryRecord;
  ratings: Ratings;
}
export function solPrimaryAssessment(
  packet: SolPrimaryPacket,
  a: SolPrimaryAssignment,
  e: Pick<SolPrimaryEntry, "record">,
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
export function solPrimaryIdentityInterpretation(
  assessment: ReturnType<typeof solPrimaryAssessment>,
) {
  if (assessment.subject === "no_result") return "no_result";
  if (assessment.subject === "unverified") return "unassessable_reference";
  // Preserve raw subject disagreement, but a predeclared reference gap is not truth.
  if (assessment.subject === "disagreement") {
    return assessment.identityReferenceLimited
      ? "unassessable_limited_reference"
      : "subject_disagreement";
  }
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
/** Continuation is a mechanics decision, not a claim of quality qualification. */
export function solPrimaryScreenDecision(
  packet: SolPrimaryPacket,
  a: SolPrimaryAssignment,
  e: SolPrimaryEntry,
): "pass" | "reference_limited" | "failed" | "unassessable" {
  if (e.record.reason !== "completed") return "failed";
  const ratings = Object.values(e.ratings);
  if (ratings.some((r) => r.status === "fail")) return "failed";
  if (
    ratings.some((r) =>
      r.status !== "pass" &&
      !(r.status === "not_assessable" && r.reason === "insufficient_reference")
    )
  ) return "unassessable";
  const s = solPrimaryAssessment(packet, a, e);
  if (
    ["unmapped", "ambiguous"].includes(e.record.mapping.status) ||
    (e.record.prediction.outcome === "normalized" &&
      e.record.prediction.resolution === "named" &&
      e.record.primaryResolution === null)
  ) return "unassessable";
  if (s.identityReferenceLimited) return "reference_limited";
  if (!ratingsPass(e.ratings)) return "unassessable";
  if (s.subject !== "agreement") return "failed";
  if (["unmapped", "ambiguous", "unverified"].includes(s.identity)) {
    return "unassessable";
  }
  return ["agreement", "valid_abstention", "not_applicable"].includes(
      s.identity,
    )
    ? "pass"
    : "failed";
}
export function solPrimarySummary(
  packet: SolPrimaryPacket,
  entries: Map<number, SolPrimaryEntry>,
  records: Map<number, SolPrimaryRecord>,
) {
  const attempts = packet.report.order.filter((a) => records.has(a.ordinal))
    .map((a) => {
      const e = entries.get(a.ordinal), record = records.get(a.ordinal)!;
      const assessment = solPrimaryAssessment(packet, a, { record });
      return {
        ordinal: a.ordinal,
        caseId: a.caseId,
        phase: a.phase,
        profile: a.profile,
        reason: record.reason,
        mapping: record.mapping.status,
        primaryResolution: record.primaryResolution,
        resolutionOrigin: record.resolutionOrigin,
        comparisonDecision: e ? solPrimaryScreenDecision(packet, a, e) : null,
        assessment,
        identityInterpretation: solPrimaryIdentityInterpretation(assessment),
        ratings: e?.ratings ?? null,
        explanationRatingsPassed: e ? ratingsPass(e.ratings) : false,
        explanationPassed: e && !assessment.identityReferenceLimited
          ? ratingsPass(e.ratings)
          : false,
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
    version: "sol_photo_primary_summary_v1",
    evidenceStatus: packet.report.evidenceStatus,
    independentTruthVerified: false,
    reusedDevelopmentCases: true,
    productionActivationAuthorized: false,
    confidenceCalibrationQualified: false,
    qualityQualified: false,
    coverage: packet.report.coverage,
    pairedChallengeCases: pairedIds.length,
    attempts,
    profiles: (["openai_photo_sol_low_v1", SOL_PRIMARY_PROFILE] as const)
      .flatMap((
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
            qualityPasses: selected.filter((a) =>
              a.comparisonDecision === "pass"
            ).length,
            referenceLimitedContinuations:
              selected.filter((a) =>
                a.comparisonDecision === "reference_limited"
              ).length,
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
            explanationPasses:
              selected.filter((a) => a.explanationPassed).length,
            explanationFailures:
              selected.filter((a) =>
                Object.values(a.ratings ?? {}).some((r) => r.status === "fail")
              ).length,
            referenceGapAttempts: selected.filter((a) =>
              Object.values(a.ratings ?? {}).some((r) =>
                r.reason === "insufficient_reference"
              )
            ).length,
            pairedTimingDenominator:
              paired.filter((a) => a.providerMs !== null).length,
            pairedProviderMedianMs: median(
              paired.flatMap((a) =>
                a.providerMs === null ? [] : [a.providerMs]
              ),
            ),
            knownCostAttempts:
              selected.filter((a) => a.estimatedUpperNanoUsd !== null).length,
            knownCostUpperUsd:
              selected.reduce((n, a) => n + (a.estimatedUpperNanoUsd ?? 0), 0) /
              1e9,
          };
        })
      ),
  };
}
