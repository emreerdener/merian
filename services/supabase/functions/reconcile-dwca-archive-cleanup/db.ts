import type { SupabaseClient } from "@supabase/supabase-js";

export interface ClaimedDwcaArchiveCleanup {
  cleanupId: string;
  jobId: string | null;
  objectKey: string;
  attemptCount: number;
}

export interface DwcaArchiveCleanupHealth {
  generatedAt: string;
  pendingCount: number;
  processingCount: number;
  expiredLeaseCount: number;
  oldestDueAt: string | null;
  oldestDueAgeSeconds: number | null;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ARCHIVE_OBJECT_KEY_PATTERN =
  /^exports\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.zip$/i;

export async function claimDwcaArchiveCleanupJobs(
  claimToken: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ClaimedDwcaArchiveCleanup[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_dwca_archive_cleanup_jobs",
    {
      p_claim_token: claimToken,
      p_limit: limit,
      p_lease_seconds: 120,
    },
  );
  if (error || !Array.isArray(data)) {
    throw new Error("Failed to claim DwCA archive cleanup jobs.");
  }
  return data.map((value) => parseClaim(value));
}

export async function completeDwcaArchiveCleanupJob(
  cleanupId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "complete_dwca_archive_cleanup_job",
    {
      p_cleanup_id: cleanupId,
      p_claim_token: claimToken,
    },
  );
  if (error || data !== true) {
    throw new Error("Failed to complete a DwCA archive cleanup job.");
  }
}

export async function releaseDwcaArchiveCleanupJob(
  cleanupId: string,
  claimToken: string,
  errorCode: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "release_dwca_archive_cleanup_job",
    {
      p_cleanup_id: cleanupId,
      p_claim_token: claimToken,
      p_error_code: errorCode,
    },
  );
  if (error || data !== true) {
    throw new Error("Failed to release a DwCA archive cleanup job.");
  }
}

export async function getDwcaArchiveCleanupHealth(
  supabaseAdmin: SupabaseClient,
): Promise<DwcaArchiveCleanupHealth> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_dwca_archive_cleanup_health",
  );
  if (error || !Array.isArray(data) || data.length !== 1) {
    throw new Error("Failed to load DwCA archive cleanup health.");
  }
  const row = data[0] as Record<string, unknown>;
  const generatedAt = timestamp(row.generated_at, "generated_at");
  const pendingCount = count(row.pending_count, "pending_count");
  const processingCount = count(row.processing_count, "processing_count");
  const expiredLeaseCount = count(
    row.expired_lease_count,
    "expired_lease_count",
  );
  const oldestDueAt = nullableTimestamp(row.oldest_due_at, "oldest_due_at");
  const oldestDueAgeSeconds = nullableCount(
    row.oldest_due_age_seconds,
    "oldest_due_age_seconds",
  );
  if ((oldestDueAt === null) !== (oldestDueAgeSeconds === null)) {
    throw new Error("DwCA cleanup health returned inconsistent due age.");
  }
  return {
    generatedAt,
    pendingCount,
    processingCount,
    expiredLeaseCount,
    oldestDueAt,
    oldestDueAgeSeconds,
  };
}

function parseClaim(value: unknown): ClaimedDwcaArchiveCleanup {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("DwCA cleanup claim was malformed.");
  }
  const row = value as Record<string, unknown>;
  if (
    typeof row.cleanup_id !== "string" ||
    !UUID_PATTERN.test(row.cleanup_id) ||
    (row.job_id !== null &&
      (typeof row.job_id !== "string" || !UUID_PATTERN.test(row.job_id))) ||
    typeof row.object_key !== "string" ||
    !ARCHIVE_OBJECT_KEY_PATTERN.test(row.object_key) ||
    !Number.isSafeInteger(row.attempt_count) ||
    Number(row.attempt_count) < 1
  ) {
    throw new Error("DwCA cleanup claim failed validation.");
  }
  return {
    cleanupId: row.cleanup_id,
    jobId: row.job_id,
    objectKey: row.object_key,
    attemptCount: Number(row.attempt_count),
  };
}

function count(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error(`DwCA cleanup health returned invalid ${field}.`);
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
    throw new Error(`DwCA cleanup health returned invalid ${field}.`);
  }
  return value;
}

function nullableTimestamp(value: unknown, field: string): string | null {
  return value === null ? null : timestamp(value, field);
}
