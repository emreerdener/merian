/**
 * Canonical confidence threshold constants for the identify pipeline.
 *
 * These values are the server-side source of truth. The iOS client mirrors them
 * in `MerianConfig.flashConfidence` and `MerianConfig.proConfidence` — any change
 * here must be reflected there, and vice versa.
 *
 * diagnosticTrigger == strong: candidates are stripped only for Strong match scans,
 * so every Possible and Weak match scan reaches the client with the full candidate
 * list for the verification UX.
 */

export const FLASH_STRONG = 0.95;
export const FLASH_POSSIBLE = 0.75;
/**
 * Server strips candidates at or above this score.
 * Intentionally above FLASH_STRONG (0.95) so candidates are preserved even
 * on "Strong match" scans — Flash can be overconfident on visually similar
 * species, and the user should always have an escape hatch below 0.99.
 */
export const FLASH_DIAGNOSTIC_TRIGGER = 0.99;

export const PRO_STRONG = 0.85;
export const PRO_POSSIBLE = 0.65;
/**
 * Server strips candidates at or above this score.
 * Same rationale as Flash: Pro is better calibrated but not infallible.
 * Candidates are suppressed only when the model is effectively certain (≥ 0.99).
 */
export const PRO_DIAGNOSTIC_TRIGGER = 0.99;

/** Returns the correct diagnostic trigger for a given user tier. */
export function diagnosticTriggerForTier(tier: "pro" | "flash"): number {
  return tier === "pro" ? PRO_DIAGNOSTIC_TRIGGER : FLASH_DIAGNOSTIC_TRIGGER;
}
