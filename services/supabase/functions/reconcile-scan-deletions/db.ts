import type { SupabaseClient } from "@supabase/supabase-js";

export interface ClaimedScanDeletion {
  scanId: string;
  userId: string;
  attemptCount: number;
}

export interface ScanDeletionHealth {
  generatedAt: string;
  pendingCount: number;
  processingCount: number;
  expiredLeaseCount: number;
  oldestPendingAt: string | null;
  oldestPendingAgeSeconds: number | null;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function claimScanDeletionJobs(
  claimToken: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ClaimedScanDeletion[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_scan_deletion_jobs",
    {
      p_claim_token: claimToken,
      p_limit: limit,
      p_lease_seconds: 120,
    },
  );
  if (error || !Array.isArray(data)) {
    throw new Error("Failed to claim scan deletion jobs.");
  }
  return data.map(parseClaim);
}

export async function releaseScanDeletionJob(
  scanId: string,
  userId: string,
  claimToken: string,
  errorCode: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "release_scan_deletion_job",
    {
      p_scan_id: scanId,
      p_user_id: userId,
      p_claim_token: claimToken,
      p_error_code: errorCode,
    },
  );
  if (error || data !== true) {
    throw new Error("Failed to release a scan deletion job.");
  }
}

export async function getScanDeletionHealth(
  supabaseAdmin: SupabaseClient,
): Promise<ScanDeletionHealth> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_scan_deletion_health",
  );
  if (error || !Array.isArray(data) || data.length !== 1) {
    throw new Error("Failed to load scan deletion health.");
  }
  return parseHealth(data[0]);
}

function parseClaim(value: unknown): ClaimedScanDeletion {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Scan deletion claim was malformed.");
  }
  const row = value as Record<string, unknown>;
  if (
    typeof row.scan_id !== "string" ||
    !UUID_PATTERN.test(row.scan_id) ||
    typeof row.user_id !== "string" ||
    !UUID_PATTERN.test(row.user_id) ||
    !Number.isSafeInteger(row.attempt_count) ||
    Number(row.attempt_count) < 1
  ) {
    throw new Error("Scan deletion claim failed validation.");
  }
  return {
    scanId: row.scan_id,
    userId: row.user_id,
    attemptCount: Number(row.attempt_count),
  };
}

function parseHealth(value: unknown): ScanDeletionHealth {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Scan deletion health was malformed.");
  }
  const row = value as Record<string, unknown>;
  const oldestPendingAt = nullableTimestamp(
    row.oldest_pending_at,
    "oldest_pending_at",
  );
  const oldestPendingAgeSeconds = nullableCount(
    row.oldest_pending_age_seconds,
    "oldest_pending_age_seconds",
  );
  if (
    (oldestPendingAt === null) !== (oldestPendingAgeSeconds === null)
  ) {
    throw new Error("Scan deletion health returned inconsistent age.");
  }
  return {
    generatedAt: timestamp(row.generated_at, "generated_at"),
    pendingCount: count(row.pending_count, "pending_count"),
    processingCount: count(row.processing_count, "processing_count"),
    expiredLeaseCount: count(
      row.expired_lease_count,
      "expired_lease_count",
    ),
    oldestPendingAt,
    oldestPendingAgeSeconds,
  };
}

function count(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error(`Scan deletion health returned invalid ${field}.`);
  }
  return Number(value);
}

function nullableCount(value: unknown, field: string): number | null {
  return value === null ? null : count(value, field);
}

function timestamp(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(`Scan deletion health returned invalid ${field}.`);
  }
  return value;
}

function nullableTimestamp(value: unknown, field: string): string | null {
  return value === null ? null : timestamp(value, field);
}
