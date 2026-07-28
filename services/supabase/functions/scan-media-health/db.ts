import { SupabaseClient } from "@supabase/supabase-js";

import {
  buildScanMediaHealthReport,
  type ExploreAudioMediaHealthRow,
  type ExploreVideoMediaHealthRow,
  type ReadyAudioAssetHealthRow,
  type ReadyVideoAssetHealthRow,
  type ReconciliationRunHealthRow,
  type ScanDeletionHealthRow,
  type ScanIngestionHealthRow,
  type ScanIngestionIntentHealthRow,
  type ScanMediaAssetHealthRow,
  type ScanMediaHealthReport,
  type ScanMediaHealthRequest,
  type ScanMediaHealthScanRow,
} from "./health.ts";

export async function fetchScanMediaHealth(
  request: ScanMediaHealthRequest,
  supabaseAdmin: SupabaseClient,
  now = new Date(),
): Promise<ScanMediaHealthReport> {
  const staleAssetCutoff = new Date(
    now.getTime() - request.staleAssetAfterMinutes * 60 * 1_000,
  ).toISOString();

  const [
    ingestionJobs,
    staleCaptureUploadAssets,
    failedAssets,
    scans,
    exploreVideoMedia,
    exploreAudioMedia,
    reconciliationRuns,
    scanDeletionHealth,
  ] = await Promise.all([
    fetchIngestionJobs(request.limit, supabaseAdmin),
    fetchStaleCaptureUploadAssets(
      staleAssetCutoff,
      request.limit,
      supabaseAdmin,
    ),
    fetchFailedAssets(request.limit, supabaseAdmin),
    fetchRecentScans(request.recentScanLimit, supabaseAdmin),
    fetchExploreVideoMedia(request.limit, supabaseAdmin),
    fetchExploreAudioMedia(request.limit, supabaseAdmin),
    fetchLatestReconciliationRuns(request.limit, supabaseAdmin),
    fetchScanDeletionHealth(supabaseAdmin),
  ]);

  const readyVideoAssets = await fetchReadyVideoAssets(
    scans.map((scan) => scan.id),
    supabaseAdmin,
  );
  const readyAudioAssets = await fetchReadyAudioAssets(
    scans.map((scan) => scan.id),
    supabaseAdmin,
  );
  const ingestionIntents = await fetchIngestionIntents(
    ingestionJobs.map((job) => job.scan_id),
    supabaseAdmin,
  );

  return buildScanMediaHealthReport({
    now,
    request,
    ingestionJobs,
    ingestionIntents,
    staleCaptureUploadAssets,
    failedAssets,
    scans,
    readyVideoAssets,
    exploreVideoMedia,
    readyAudioAssets,
    exploreAudioMedia,
    reconciliationRuns,
    scanDeletionHealth,
  });
}

async function fetchScanDeletionHealth(
  supabaseAdmin: SupabaseClient,
): Promise<ScanDeletionHealthRow> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_scan_deletion_health",
  );
  if (error || !Array.isArray(data) || data.length !== 1) {
    throw new Error("fetchScanDeletionHealth: unavailable");
  }
  const row = data[0] as Record<string, unknown>;
  const generatedAt = healthTimestamp(row.generated_at, "generated_at");
  const pendingCount = healthCount(row.pending_count, "pending_count");
  const processingCount = healthCount(
    row.processing_count,
    "processing_count",
  );
  const expiredLeaseCount = healthCount(
    row.expired_lease_count,
    "expired_lease_count",
  );
  const oldestPendingAt = row.oldest_pending_at === null
    ? null
    : healthTimestamp(row.oldest_pending_at, "oldest_pending_at");
  const oldestPendingAgeSeconds = row.oldest_pending_age_seconds === null
    ? null
    : healthCount(
      row.oldest_pending_age_seconds,
      "oldest_pending_age_seconds",
    );
  if (
    (oldestPendingAt === null) !== (oldestPendingAgeSeconds === null)
  ) {
    throw new Error("fetchScanDeletionHealth: inconsistent age");
  }
  return {
    generated_at: generatedAt,
    pending_count: pendingCount,
    processing_count: processingCount,
    expired_lease_count: expiredLeaseCount,
    oldest_pending_at: oldestPendingAt,
    oldest_pending_age_seconds: oldestPendingAgeSeconds,
  };
}

function healthCount(value: unknown, field: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error(`fetchScanDeletionHealth: invalid ${field}`);
  }
  return Number(value);
}

function healthTimestamp(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(`fetchScanDeletionHealth: invalid ${field}`);
  }
  return value;
}

async function fetchIngestionIntents(
  scanIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionIntentHealthRow[]> {
  const uniqueScanIds = [...new Set(scanIds.map((id) => id.trim()))].filter((
    id,
  ) => id.length > 0);
  if (uniqueScanIds.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scan_ingestion_intents")
    .select(
      [
        "scan_id",
        "user_id",
        "manifest_checksum",
        "payload_checksum",
        "resumable",
        "inline_media_redacted",
        "redacted_media_counts",
        "updated_at",
      ].join(","),
    )
    .in("scan_id", uniqueScanIds)
    .limit(uniqueScanIds.length);

  if (error) {
    throw new Error(`fetchIngestionIntents: ${error.message}`);
  }

  return (data ?? []) as unknown as ScanIngestionIntentHealthRow[];
}

async function fetchIngestionJobs(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionHealthRow[]> {
  const [activeRows, recentCompleteRows] = await Promise.all([
    fetchIngestionJobsByStatus(
      [
        "processing",
        "finalizing",
        "retrying",
        "failed_retryable",
        "failed_terminal",
      ],
      limit,
      "oldest",
      supabaseAdmin,
    ),
    fetchIngestionJobsByStatus(
      ["complete"],
      limit,
      "newest",
      supabaseAdmin,
    ),
  ]);

  const rowsByScanId = new Map<string, ScanIngestionHealthRow>();
  for (const row of [...activeRows, ...recentCompleteRows]) {
    rowsByScanId.set(row.scan_id, row);
  }
  return [...rowsByScanId.values()];
}

async function fetchIngestionJobsByStatus(
  statuses: string[],
  limit: number,
  order: "newest" | "oldest",
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionHealthRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    .select(
      [
        "scan_id",
        "user_id",
        "status",
        "stage",
        "attempt_count",
        "media_counts",
        "locked_at",
        "lock_expires_at",
        "retry_after",
        "last_error",
        "created_at",
        "updated_at",
      ].join(","),
    )
    .in("status", statuses)
    .order("updated_at", {
      ascending: order === "oldest",
      nullsFirst: order === "oldest",
    })
    .limit(limit);

  if (error) {
    throw new Error(`fetchIngestionJobsByStatus: ${error.message}`);
  }

  return (data ?? []) as unknown as ScanIngestionHealthRow[];
}

async function fetchStaleCaptureUploadAssets(
  cutoffIso: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ScanMediaAssetHealthRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select(mediaAssetSelect())
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .lte("created_at", cutoffIso)
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    throw new Error(`fetchStaleCaptureUploadAssets: ${error.message}`);
  }

  return (data ?? []) as unknown as ScanMediaAssetHealthRow[];
}

async function fetchFailedAssets(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ScanMediaAssetHealthRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select(mediaAssetSelect())
    .eq("status", "failed")
    .order("updated_at", { ascending: false, nullsFirst: false })
    .limit(limit);

  if (error) {
    throw new Error(`fetchFailedAssets: ${error.message}`);
  }

  return (data ?? []) as unknown as ScanMediaAssetHealthRow[];
}

async function fetchRecentScans(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ScanMediaHealthScanRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,timestamp,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media",
    )
    .eq("is_tombstoned", false)
    .order("timestamp", { ascending: false, nullsFirst: false })
    .limit(limit);

  if (error) {
    throw new Error(`fetchRecentScans: ${error.message}`);
  }

  return (data ?? []) as unknown as ScanMediaHealthScanRow[];
}

async function fetchReadyAudioAssets(
  scanIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ReadyAudioAssetHealthRow[]> {
  const ids = [...new Set(scanIds.filter((id) => id.trim()))];
  if (!ids.length) return [];
  const { data, error } = await supabaseAdmin.from("scan_media_assets")
    .select("id,scan_id,url").in("scan_id", ids).eq("kind", "audio")
    .eq("role", "audio").eq("status", "ready");
  if (error) throw new Error(`fetchReadyAudioAssets: ${error.message}`);
  return (data ?? []) as unknown as ReadyAudioAssetHealthRow[];
}

async function fetchExploreAudioMedia(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreAudioMediaHealthRow[]> {
  const { data, error } = await supabaseAdmin.from("explore_post_media")
    .select("id,post_id,url,created_at,updated_at").eq("kind", "audio")
    .order("updated_at", { ascending: false, nullsFirst: false }).limit(limit);
  if (error) throw new Error(`fetchExploreAudioMedia: ${error.message}`);
  return (data ?? []) as unknown as ExploreAudioMediaHealthRow[];
}

async function fetchReadyVideoAssets(
  scanIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ReadyVideoAssetHealthRow[]> {
  const uniqueScanIds = [...new Set(scanIds.map((id) => id.trim()))].filter((
    id,
  ) => id.length > 0);
  if (uniqueScanIds.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select("id,scan_id,url,thumbnail_url")
    .in("scan_id", uniqueScanIds)
    .eq("kind", "video")
    .eq("role", "playback")
    .eq("status", "ready")
    .order("order_index", { ascending: true });

  if (error) {
    throw new Error(`fetchReadyVideoAssets: ${error.message}`);
  }

  return (data ?? []) as unknown as ReadyVideoAssetHealthRow[];
}

async function fetchExploreVideoMedia(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreVideoMediaHealthRow[]> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_media")
    .select("id,post_id,url,thumbnail_url,created_at,updated_at")
    .eq("kind", "video")
    .order("updated_at", { ascending: false, nullsFirst: false })
    .limit(limit);

  if (error) {
    throw new Error(`fetchExploreVideoMedia: ${error.message}`);
  }

  return (data ?? []) as unknown as ExploreVideoMediaHealthRow[];
}

async function fetchLatestReconciliationRuns(
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ReconciliationRunHealthRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_reconciliation_runs")
    .select("id,status,error_count,errors,started_at,finished_at,created_at")
    .order("started_at", { ascending: false, nullsFirst: false })
    .limit(limit);

  if (error) {
    throw new Error(`fetchLatestReconciliationRuns: ${error.message}`);
  }

  return (data ?? []) as unknown as ReconciliationRunHealthRow[];
}

function mediaAssetSelect(): string {
  return [
    "id",
    "scan_id",
    "client_scan_id",
    "user_id",
    "kind",
    "role",
    "status",
    "source",
    "url",
    "storage_key",
    "thumbnail_url",
    "failure_reason",
    "created_at",
    "updated_at",
  ].join(",");
}
