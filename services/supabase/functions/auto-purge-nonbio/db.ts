import type { SupabaseClient } from "@supabase/supabase-js";

const MAXIMUM_RETENTION_BATCH_SIZE = 500;

/**
 * Atomically selects, generation-locks, revalidates, and fences one bounded
 * batch of expired non-biological scans. External media erasure is deliberately
 * owned by reconcile-scan-deletions rather than this request.
 */
export async function requestNonBiologicalScanRetentionDeletions(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  if (
    !Number.isSafeInteger(limit) ||
    limit < 1 ||
    limit > MAXIMUM_RETENTION_BATCH_SIZE
  ) {
    throw new Error("Invalid non-biological retention batch size.");
  }

  const { data, error } = await supabaseAdmin.rpc(
    "request_nonbiological_scan_retention_deletions",
    { p_limit: limit },
  );

  if (
    error ||
    !Number.isSafeInteger(data) ||
    Number(data) < 0 ||
    Number(data) > limit
  ) {
    throw new Error(
      "Failed to request non-biological scan retention deletions.",
    );
  }

  return Number(data);
}
