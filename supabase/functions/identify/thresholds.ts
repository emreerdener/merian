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

export const FLASH_STRONG = 0.96;
export const FLASH_POSSIBLE = 0.75;
/** Server strips candidates at or above this score (== FLASH_STRONG). */
export const FLASH_DIAGNOSTIC_TRIGGER = 0.96;

export const PRO_STRONG = 0.85;
export const PRO_POSSIBLE = 0.65;
/** Server strips candidates at or above this score (== PRO_STRONG). */
export const PRO_DIAGNOSTIC_TRIGGER = 0.85;

/** Returns the correct diagnostic trigger for a given user tier. */
export function diagnosticTriggerForTier(tier: "pro" | "flash"): number {
  return tier === "pro" ? PRO_DIAGNOSTIC_TRIGGER : FLASH_DIAGNOSTIC_TRIGGER;
}
