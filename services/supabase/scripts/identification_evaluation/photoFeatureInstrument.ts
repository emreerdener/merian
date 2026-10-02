/** Private in-memory review: only IDs, hashes and categorical verdicts persist. */
import type { PhotoFeature } from "./photoFeatureCandidate.ts";
import { FEATURE_KINDS, FEATURE_VISIBILITY } from "./photoFeatureCandidate.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  array,
  fields,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";

export interface FeatureReviewItem {
  support: "supported" | "contradicted" | "unverifiable" | "irrelevant";
  visibilityAccurate: boolean;
  diagnosticValue: "distinguishing" | "shared" | "uninformative";
}
export interface BlindFeatureView {
  token: string;
  facts: readonly string[];
  image: { sha256: string; mimeType: string; data: string };
  features: readonly Readonly<PhotoFeature>[];
}
export interface FeatureReviewer {
  id: string;
  method: "local_interactive" | "synthetic";
  review: (view: Readonly<BlindFeatureView>) => Promise<unknown>;
}
export interface FeatureReviewReceipt {
  version: "photo_feature_instrument_v1";
  token: string;
  imageDigest: string;
  featureDigest: string;
  cardDigest: string;
  traits: Pick<PhotoFeature, "kind" | "visibility">[];
  reviewers: { id: string; method: FeatureReviewer["method"] }[];
  verdicts: FeatureReviewItem[][];
  disagreements: number;
  eligible: boolean;
}
export function featureJudgments(
  value: unknown,
  count: number,
): FeatureReviewItem[] {
  return array(value, count, count).map((raw) => {
    const v = fields(raw, ["support", "visibilityAccurate", "diagnosticValue"]);
    member(v.support, [
      "supported",
      "contradicted",
      "unverifiable",
      "irrelevant",
    ]);
    check(typeof v.visibilityAccurate === "boolean");
    member(v.diagnosticValue, ["distinguishing", "shared", "uninformative"]);
    return { ...v } as unknown as FeatureReviewItem;
  });
}
const good = (j: FeatureReviewItem) =>
  j.support === "supported" && j.visibilityAccurate &&
  j.diagnosticValue !== "uninformative";
const equal = (a: FeatureReviewItem, b: FeatureReviewItem) =>
  a.support === b.support && a.visibilityAccurate === b.visibilityAccurate &&
  a.diagnosticValue === b.diagnosticValue;

export function reviewerSlot(value: unknown): asserts value is string {
  check(value === "slot-01" || value === "slot-02");
}
export function validateFeatureReviewers(
  reviewers: readonly FeatureReviewer[],
) {
  check(reviewers.length === 2);
  reviewers.forEach((r) => {
    reviewerSlot(r.id);
    member(r.method, ["local_interactive", "synthetic"]);
    check(typeof r.review === "function");
  });
  check(
    reviewers[0].id !== reviewers[1].id &&
      reviewers[0].review !== reviewers[1].review,
  );
}

/** Validates the durable allowlist and derives credit, never trusts a saved flag. */
export function parseFeatureReviewReceipt(
  value: unknown,
): FeatureReviewReceipt {
  const r = fields(value, [
    "version",
    "token",
    "imageDigest",
    "featureDigest",
    "cardDigest",
    "traits",
    "reviewers",
    "verdicts",
    "disagreements",
    "eligible",
  ]);
  check(r.version === "photo_feature_instrument_v1");
  token(r.token);
  for (const hash of [r.imageDigest, r.featureDigest, r.cardDigest]) {
    check(typeof hash === "string" && /^[a-f0-9]{64}$/.test(hash));
  }
  const reviewers = array(r.reviewers, 2, 2).map((raw) => {
    const v = fields(raw, ["id", "method"]);
    reviewerSlot(v.id);
    member(v.method, ["local_interactive", "synthetic"] as const);
    return { id: v.id, method: v.method };
  });
  check(reviewers[0].id !== reviewers[1].id);
  const raw = array(r.verdicts, 2, 2);
  const count = array(raw[0], 0, 3).length;
  const traits = array(r.traits, count, count).map((raw) => {
    const t = fields(raw, ["kind", "visibility"]);
    member(t.kind, FEATURE_KINDS);
    member(t.visibility, FEATURE_VISIBILITY);
    return t as unknown as Pick<PhotoFeature, "kind" | "visibility">;
  });
  const verdicts = raw.map((v) => featureJudgments(v, count));
  const disagreements =
    verdicts[0].filter((v, i) => !equal(v, verdicts[1][i])).length;
  const eligible = count > 0 && disagreements === 0 &&
    verdicts.every((v) => v.every(good));
  check(r.disagreements === disagreements && r.eligible === eligible);
  return {
    version: "photo_feature_instrument_v1",
    token: r.token,
    imageDigest: r.imageDigest as string,
    featureDigest: r.featureDigest as string,
    cardDigest: r.cardDigest as string,
    reviewers,
    traits,
    verdicts,
    disagreements,
    eligible,
  };
}

/**
 * Two separate reviewer slots provide conservative double coding, not adjudication.
 * No first-review verdict is revealed. Remaining disagreement earns no credit.
 * Function/ID separation is auditable assignment, not proof of independence.
 * Integrations are trusted to keep their input transient and treat text as data.
 */
export async function reviewFeatureView(
  view: BlindFeatureView,
  reviewers: readonly FeatureReviewer[],
) {
  validateFeatureReviewers(reviewers);
  token(view.token);
  check(/^[a-f0-9]{64}$/.test(view.image.sha256));
  for (const f of array(view.features, 0, 3) as PhotoFeature[]) {
    member(f.kind, FEATURE_KINDS);
    member(f.visibility, FEATURE_VISIBILITY);
  }
  const featureDigest = await fingerprintJson(view.features);
  const verdicts: FeatureReviewItem[][] = [];
  for (const r of reviewers) {
    const copy = Object.freeze({
      token: view.token,
      facts: Object.freeze([...view.facts]),
      image: Object.freeze({ ...view.image }),
      features: Object.freeze(
        view.features.map((f) => Object.freeze({ ...f })),
      ),
    });
    verdicts.push(featureJudgments(await r.review(copy), view.features.length));
  }
  const disagreements =
    verdicts[0].filter((v, i) => !equal(v, verdicts[1][i])).length;
  return parseFeatureReviewReceipt({
    version: "photo_feature_instrument_v1",
    token: view.token,
    imageDigest: view.image.sha256,
    featureDigest,
    cardDigest: await fingerprintJson(view.facts),
    traits: view.features.map(({ kind, visibility }) => ({ kind, visibility })),
    reviewers: reviewers.map((r) => ({ id: r.id, method: r.method })),
    verdicts,
    disagreements,
    eligible: view.features.length > 0 && disagreements === 0 &&
      verdicts.every((v) => v.every(good)),
  });
}
