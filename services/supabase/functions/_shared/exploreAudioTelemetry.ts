export function moderationLatencyBucket(elapsedMs: number): string {
  if (elapsedMs < 1_000) return "under_1s";
  if (elapsedMs < 3_000) return "1_to_3s";
  if (elapsedMs < 10_000) return "3_to_10s";
  return "over_10s";
}

export function exploreShareFailureReason(error: unknown): string {
  const status = error && typeof error === "object" && "status" in error
    ? Number(error.status)
    : 500;
  if (status === 422) return "moderation_rejected";
  if (status === 503) return "dependency_unavailable";
  if (status >= 400 && status < 500) return "request_rejected";
  return "publication_failed";
}
