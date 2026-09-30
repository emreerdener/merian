/** Frozen assessment policy. Changing any rule requires a new version/study. */
export const CONFIDENCE_PROTOCOL = Object.freeze({
  version: "identification_openai_confidence_assessment_v1",
  corpusVersion: "openai_confidence_corpus_v2",
  referenceReviewMethod: "source_grounded_visibility_v1",
  scorerVersion: "openai_confidence_decisions_v1",
  splitSeed: 20260930,
  casesPerSplit: 100,
  maxAttempts: 200,
  budgetNanoUsd: 10_000_000_000,
  possible: 0.60,
  fallbackStrong: 0.95,
  minimumStrongCount: 40,
  minimumPrecision: 0.95,
  cutoffs: Object.freeze(Array.from({ length: 40 }, (_, i) => (61 + i) / 100)),
  bins: Object.freeze(
    [[0, .60], [.60, .70], [.70, .80], [.80, .90], [.90, .95], [.95, 1]]
      .map(([min, max]) =>
        Object.freeze({ min, max, inclusiveMax: max === 1 })
      ),
  ),
  interval: "wilson_95_two_sided",
  categories: Object.freeze(
    ["clear", "lookalike", "limited", "cultivated", "nonbiological"] as const,
  ),
  taxaGroups: Object.freeze(
    ["plant", "fungus", "invertebrate", "vertebrate"] as const,
  ),
});
export type ConfidenceCategory = typeof CONFIDENCE_PROTOCOL.categories[number];
export type ConfidenceGroup =
  | typeof CONFIDENCE_PROTOCOL.taxaGroups[number]
  | "none";

export function confidenceRate(numerator: number, denominator: number) {
  if (
    !Number.isSafeInteger(numerator) || !Number.isSafeInteger(denominator) ||
    numerator < 0 || numerator > denominator
  ) throw new Error("invalid_rate");
  if (denominator === 0) {
    return {
      numerator,
      denominator,
      value: null,
      interval: null,
      status: "not_estimable" as const,
    };
  }
  const z = 1.959963984540054, z2 = z * z, p = numerator / denominator;
  const divisor = 1 + z2 / denominator;
  const center = (p + z2 / (2 * denominator)) / divisor;
  const half = z *
    Math.sqrt(p * (1 - p) / denominator + z2 / (4 * denominator ** 2)) /
    divisor;
  return {
    numerator,
    denominator,
    value: p,
    interval: {
      lower: Math.max(0, center - half),
      upper: Math.min(1, center + half),
    },
    status: "measured" as const,
  };
}
