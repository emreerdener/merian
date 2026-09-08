export const LEGACY_PREPARED_HANDOFF_WARNING_COUNT = 100;
export const LEGACY_PREPARED_HANDOFF_CRITICAL_COUNT = 500;

export type LegacyPreparedHandoffVolumeStatus =
  | "ok"
  | "warning"
  | "critical";

export function legacyPreparedHandoffVolumeStatus(
  preparedCount: number,
): LegacyPreparedHandoffVolumeStatus {
  if (preparedCount >= LEGACY_PREPARED_HANDOFF_CRITICAL_COUNT) {
    return "critical";
  }
  if (preparedCount >= LEGACY_PREPARED_HANDOFF_WARNING_COUNT) {
    return "warning";
  }
  return "ok";
}

/**
 * Legacy health exposes one combined oldest age for prepared and bound proofs.
 * A prepared proof has not moved a StoreKit receipt and remains recoverable by
 * its originating device. Once any proof is bound, the combined age is a
 * conservative upper bound for actionable sign-out work.
 */
export function actionableLegacySignoutAgeSeconds(
  boundCount: number,
  combinedOldestAgeSeconds: number | null,
): number {
  return boundCount > 0 ? combinedOldestAgeSeconds ?? 0 : 0;
}
