export const DEFAULT_SCAN_INGESTION_RETRY_SECONDS = 30;

export function scanIngestionRetryAfterIso(
  nowMilliseconds = Date.now(),
): string {
  return new Date(
    nowMilliseconds + DEFAULT_SCAN_INGESTION_RETRY_SECONDS * 1_000,
  ).toISOString();
}
