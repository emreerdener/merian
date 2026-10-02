/** Trusted transient reviewers supply judgments; the model cannot grade itself. */
import {
  decodePhotoFeatureDraft,
  type PhotoFeature,
} from "./photoFeatureCandidate.ts";
import { projectDevelopmentDraft } from "./developmentProjection.ts";
import type { ReviewedTaxonomy } from "./taxonomy.ts";
import { array, member, token } from "./validation.ts";

const JUDGMENTS = [
  "supported",
  "contradicted",
  "unverifiable",
  "irrelevant",
] as const;
export type FeatureJudgment = typeof JUDGMENTS[number];
export type TransientFeatureReviewer = (
  blindToken: string,
  features: readonly Readonly<PhotoFeature>[],
) => Promise<unknown>;

/**
 * Review callbacks are trusted integrations, never values parsed from the model.
 * They receive no predicted taxon, rank, confidence, explanation or result.
 * The caller owns shuffled opaque tokens and access to the exact image/cards.
 * No I/O occurs here. Never persist draft/features; persist only this projection.
 */
export async function projectReviewedPhotoFeatures(
  caseId: string,
  blindToken: string,
  raw: unknown,
  taxonomy: ReviewedTaxonomy,
  reviewers: readonly [TransientFeatureReviewer, TransientFeatureReviewer],
) {
  token(caseId);
  token(blindToken);
  let decoded: ReturnType<typeof decodePhotoFeatureDraft>;
  try {
    decoded = decodePhotoFeatureDraft(raw);
  } catch {
    return {
      version: "photo_feature_review_v1" as const,
      status: "invalid_output" as const,
    };
  }
  const projection = projectDevelopmentDraft(
    caseId,
    "explicit_primary",
    decoded.identification,
    taxonomy,
  );
  if (projection.observation.prediction.outcome !== "normalized") {
    return {
      version: "photo_feature_review_v1" as const,
      status: "invalid_output" as const,
      projection,
    };
  }
  const judgments: FeatureJudgment[][] = [];
  try {
    if (reviewers.length !== 2 || reviewers[0] === reviewers[1]) {
      throw new Error("distinct_reviewers_required");
    }
    // Separate frozen copies prevent one reviewer from steering the other.
    for (const reviewer of reviewers) {
      const view = Object.freeze(
        decoded.features.map((f) => Object.freeze({ ...f })),
      );
      const result = array(
        await reviewer(blindToken, view),
        view.length,
        view.length,
      );
      result.forEach((v) => member(v, JUDGMENTS));
      judgments.push([...result] as FeatureJudgment[]);
    }
    if (judgments.length !== 2) throw new Error("missing_review");
  } catch {
    return {
      version: "photo_feature_review_v1" as const,
      status: "review_incomplete" as const,
      projection,
    };
  }
  const count = decoded.features.length;
  const disputed = judgments[0].filter((v, i) => v !== judgments[1][i]).length;
  const supported =
    judgments[0].filter((v, i) =>
      v === "supported" && judgments[1][i] === "supported"
    ).length;
  return {
    version: "photo_feature_review_v1" as const,
    status: "reviewed" as const,
    projection,
    review: {
      count,
      supported,
      disputed,
      unsupported: count - supported,
      // Empty non-biological observations are valid but never feature-gain evidence.
      allFeaturesSupported: count > 0 && supported === count,
    },
  };
}
