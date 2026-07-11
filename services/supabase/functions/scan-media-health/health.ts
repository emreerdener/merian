export type ScanMediaHealthStatus = "ok" | "warning" | "critical";
export type ScanMediaHealthSeverity = "warning" | "critical";

export const DEFAULT_HEALTH_LIMIT = 25;
export const MAX_HEALTH_LIMIT = 100;
export const DEFAULT_STUCK_AFTER_MINUTES = 20;
export const DEFAULT_STALE_ASSET_AFTER_MINUTES = 15;
export const DEFAULT_RECENT_SCAN_LIMIT = 250;
export const MAX_RECENT_SCAN_LIMIT = 1_000;

export interface ScanMediaHealthRequest {
  limit: number;
  stuckAfterMinutes: number;
  staleAssetAfterMinutes: number;
  recentScanLimit: number;
}

export interface ParseScanMediaHealthRequestResult {
  request?: ScanMediaHealthRequest;
  error?: string;
  status?: number;
}

export interface ScanIngestionHealthRow {
  scan_id: string;
  user_id: string;
  status: string;
  stage: string;
  attempt_count: number;
  media_counts?: unknown;
  locked_at?: string | null;
  lock_expires_at?: string | null;
  retry_after?: string | null;
  last_error?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface ScanIngestionIntentHealthRow {
  scan_id: string;
  user_id: string;
  manifest_checksum?: string | null;
  payload_checksum?: string | null;
  resumable: boolean;
  inline_media_redacted: boolean;
  redacted_media_counts?: unknown;
  updated_at?: string | null;
}

export interface ScanMediaAssetHealthRow {
  id: string;
  scan_id: string | null;
  client_scan_id: string | null;
  user_id: string;
  kind: string;
  role: string;
  status: string;
  source: string;
  url: string | null;
  storage_key: string | null;
  thumbnail_url?: string | null;
  failure_reason?: string | null;
  created_at: string;
  updated_at: string;
}

export interface ScanMediaHealthScanRow {
  id: string;
  user_id: string;
  timestamp?: string | null;
  image_storage_urls: unknown;
  video_storage_urls: unknown;
  audio_storage_urls?: unknown;
  captured_media: unknown;
}

export interface ReadyAudioAssetHealthRow {
  id: string;
  scan_id: string | null;
  url: string | null;
}

export interface ExploreAudioMediaHealthRow {
  id: string;
  post_id: string;
  url: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface ReadyVideoAssetHealthRow {
  id: string;
  scan_id: string | null;
  url: string | null;
  thumbnail_url: string | null;
}

export interface ExploreVideoMediaHealthRow {
  id: string;
  post_id: string;
  url: string | null;
  thumbnail_url: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface ReconciliationRunHealthRow {
  id: string;
  status: string;
  error_count: number;
  errors: unknown;
  started_at?: string | null;
  finished_at?: string | null;
  created_at?: string | null;
}

export interface ScanMediaHealthIssue {
  code: string;
  severity: ScanMediaHealthSeverity;
  message: string;
  count: number;
  sample: Array<Record<string, unknown>>;
}

export interface ScanMediaHealthReport {
  generated_at: string;
  status: ScanMediaHealthStatus;
  thresholds: {
    stuck_after_minutes: number;
    stale_asset_after_minutes: number;
  };
  asset_breakdown: {
    stale_capture_upload_assets: ScanMediaAssetBreakdown[];
    failed_assets: ScanMediaAssetBreakdown[];
  };
  counts: {
    ingestion_jobs_checked: number;
    stale_capture_upload_assets: number;
    failed_assets: number;
    recent_scans_checked: number;
    ready_video_assets_checked: number;
    explore_video_rows_checked: number;
    ready_audio_assets_checked: number;
    explore_audio_rows_checked: number;
    reconciliation_runs_checked: number;
    ingestion_intents_checked: number;
    issues: number;
    critical_issues: number;
    warning_issues: number;
  };
  issues: ScanMediaHealthIssue[];
}

export interface ScanMediaAssetBreakdown {
  kind: string;
  role: string;
  count: number;
}

export interface BuildScanMediaHealthReportInput {
  now: Date;
  request: ScanMediaHealthRequest;
  ingestionJobs: ScanIngestionHealthRow[];
  ingestionIntents: ScanIngestionIntentHealthRow[];
  staleCaptureUploadAssets: ScanMediaAssetHealthRow[];
  failedAssets: ScanMediaAssetHealthRow[];
  scans: ScanMediaHealthScanRow[];
  readyVideoAssets: ReadyVideoAssetHealthRow[];
  exploreVideoMedia: ExploreVideoMediaHealthRow[];
  readyAudioAssets: ReadyAudioAssetHealthRow[];
  exploreAudioMedia: ExploreAudioMediaHealthRow[];
  reconciliationRuns: ReconciliationRunHealthRow[];
}

const ACTIVE_JOB_STATUSES = new Set(["processing", "finalizing", "retrying"]);
const RESUMABLE_JOB_STATUSES = new Set([
  "processing",
  "finalizing",
  "retrying",
  "failed_retryable",
]);

export function parseScanMediaHealthRequest(
  body: Record<string, unknown> = {},
): ParseScanMediaHealthRequestResult {
  const limit = parsePositiveInteger(
    body.limit,
    "limit",
    DEFAULT_HEALTH_LIMIT,
    MAX_HEALTH_LIMIT,
  );
  if (limit.error) return limit;

  const stuckAfter = parsePositiveInteger(
    body.stuck_after_minutes ?? body.stuckAfterMinutes,
    "stuck_after_minutes",
    DEFAULT_STUCK_AFTER_MINUTES,
    24 * 60,
  );
  if (stuckAfter.error) return stuckAfter;

  const staleAssetAfter = parsePositiveInteger(
    body.stale_asset_after_minutes ?? body.staleAssetAfterMinutes,
    "stale_asset_after_minutes",
    DEFAULT_STALE_ASSET_AFTER_MINUTES,
    24 * 60,
  );
  if (staleAssetAfter.error) return staleAssetAfter;

  const recentScanLimit = parsePositiveInteger(
    body.recent_scan_limit ?? body.recentScanLimit,
    "recent_scan_limit",
    DEFAULT_RECENT_SCAN_LIMIT,
    MAX_RECENT_SCAN_LIMIT,
  );
  if (recentScanLimit.error) return recentScanLimit;

  return {
    request: {
      limit: limit.value ?? DEFAULT_HEALTH_LIMIT,
      stuckAfterMinutes: stuckAfter.value ?? DEFAULT_STUCK_AFTER_MINUTES,
      staleAssetAfterMinutes: staleAssetAfter.value ??
        DEFAULT_STALE_ASSET_AFTER_MINUTES,
      recentScanLimit: recentScanLimit.value ?? DEFAULT_RECENT_SCAN_LIMIT,
    },
  };
}

export function buildScanMediaHealthReport(
  input: BuildScanMediaHealthReportInput,
): ScanMediaHealthReport {
  const issues: ScanMediaHealthIssue[] = [];
  const nowMs = input.now.getTime();
  const stuckCutoffMs = nowMs -
    input.request.stuckAfterMinutes * 60 * 1_000;

  const stuckJobs = input.ingestionJobs.filter((job) => {
    if (!ACTIVE_JOB_STATUSES.has(job.status)) return false;
    const updatedAtMs = timeValue(job.updated_at ?? job.created_at);
    const lockExpiresAtMs = timeValue(job.lock_expires_at);
    return (updatedAtMs !== null && updatedAtMs <= stuckCutoffMs) ||
      (lockExpiresAtMs !== null && lockExpiresAtMs <= nowMs);
  });
  addIssue(issues, {
    code: "stuck_ingestion_jobs",
    severity: "critical",
    message:
      "Scan ingestion jobs are still active past their expected lease window.",
    rows: stuckJobs,
    sample: sampleJob,
    limit: input.request.limit,
  });

  const retryablePastDue = input.ingestionJobs.filter((job) => {
    if (job.status !== "failed_retryable") return false;
    const retryAfterMs = timeValue(job.retry_after);
    return retryAfterMs !== null && retryAfterMs <= nowMs;
  });
  addIssue(issues, {
    code: "retryable_ingestion_jobs_past_due",
    severity: "warning",
    message:
      "Retryable scan ingestion jobs are past retry_after and should be retried or inspected.",
    rows: retryablePastDue,
    sample: sampleJob,
    limit: input.request.limit,
  });

  const intentsByJobKey = new Map(
    input.ingestionIntents.map((intent) => [jobKey(intent), intent]),
  );
  const resumableCandidateJobs = input.ingestionJobs.filter((job) =>
    RESUMABLE_JOB_STATUSES.has(job.status)
  );
  const jobsMissingIntent = resumableCandidateJobs.filter((job) =>
    !intentsByJobKey.has(jobKey(job))
  );
  addIssue(issues, {
    code: "ingestion_jobs_missing_intent",
    severity: "warning",
    message:
      "Retryable or in-flight scan ingestion jobs do not have a persisted server replay intent.",
    rows: jobsMissingIntent,
    sample: sampleJob,
    limit: input.request.limit,
  });

  const jobsWithNonResumableIntent = resumableCandidateJobs
    .map((job) => ({ job, intent: intentsByJobKey.get(jobKey(job)) }))
    .filter((entry): entry is {
      job: ScanIngestionHealthRow;
      intent: ScanIngestionIntentHealthRow;
    } => entry.intent != null && !entry.intent.resumable);
  addIssue(issues, {
    code: "ingestion_intents_not_resumable",
    severity: "warning",
    message:
      "Scan ingestion intents exist but cannot be replayed server-side because inline media was redacted.",
    rows: jobsWithNonResumableIntent,
    sample: ({ job, intent }) => ({
      ...sampleJob(job),
      ...sampleIntent(intent),
    }),
    limit: input.request.limit,
  });

  const terminalFailures = input.ingestionJobs.filter((job) =>
    job.status === "failed_terminal"
  );
  addIssue(issues, {
    code: "terminal_ingestion_failures",
    severity: "warning",
    message:
      "Scan ingestion jobs reached terminal failure and may need operator review if unexpected.",
    rows: terminalFailures,
    sample: sampleJob,
    limit: input.request.limit,
  });

  addIssue(issues, {
    code: "stale_capture_upload_assets",
    severity: "warning",
    message:
      "Capture-upload media assets remain staged past the reconciliation window.",
    rows: input.staleCaptureUploadAssets,
    sample: sampleAsset,
    limit: input.request.limit,
  });

  addIssue(issues, {
    code: "failed_scan_media_assets",
    severity: "warning",
    message:
      "Scan media assets are marked failed and may need operator review.",
    rows: input.failedAssets,
    sample: sampleAsset,
    limit: input.request.limit,
  });

  const readyVideoCounts = new Map<string, number>();
  for (const asset of input.readyVideoAssets) {
    if (!asset.scan_id) continue;
    if (!cleanString(asset.url)) continue;
    readyVideoCounts.set(
      asset.scan_id,
      (readyVideoCounts.get(asset.scan_id) ?? 0) + 1,
    );
  }

  const readyAudioCounts = new Map<string, number>();
  for (const asset of input.readyAudioAssets) {
    if (!asset.scan_id || !cleanString(asset.url)) continue;
    readyAudioCounts.set(
      asset.scan_id,
      (readyAudioCounts.get(asset.scan_id) ?? 0) + 1,
    );
  }

  const audioScansMissingManifest = input.scans.filter((scan) =>
    cleanStringArray(scan.audio_storage_urls).length > 0 &&
    !hasCapturedAudio(scan.captured_media)
  );
  addIssue(issues, {
    code: "audio_scan_missing_captured_media_audio",
    severity: "critical",
    message:
      "Scans have durable audio URLs but no audio item in captured_media.",
    rows: audioScansMissingManifest,
    sample: sampleScan,
    limit: input.request.limit,
  });

  const audioScansMissingReadyAssets = input.scans.filter((scan) => {
    const audioCount = cleanStringArray(scan.audio_storage_urls).length;
    return audioCount > 0 && (readyAudioCounts.get(scan.id) ?? 0) < audioCount;
  });
  addIssue(issues, {
    code: "audio_scan_missing_ready_audio_asset",
    severity: "critical",
    message: "Scans have durable audio URLs but fewer ready audio assets.",
    rows: audioScansMissingReadyAssets,
    sample: (row) => ({
      ...sampleScan(row),
      ready_audio_asset_count: readyAudioCounts.get(row.id) ?? 0,
    }),
    limit: input.request.limit,
  });

  const exploreAudioMissingUrls = input.exploreAudioMedia.filter((row) =>
    !cleanString(row.url)
  );
  addIssue(issues, {
    code: "explore_audio_missing_url",
    severity: "critical",
    message: "Public Explore audio rows are missing playable URLs.",
    rows: exploreAudioMissingUrls,
    sample: (row) => ({ id: row.id, post_id: row.post_id, url: row.url }),
    limit: input.request.limit,
  });

  const videoScansMissingManifest = input.scans.filter((scan) => {
    const videoCount = cleanStringArray(scan.video_storage_urls).length;
    return videoCount > 0 && !hasCapturedVideo(scan.captured_media);
  });
  addIssue(issues, {
    code: "video_scan_missing_captured_media_video",
    severity: "critical",
    message:
      "Scans have durable video URLs but no video item in captured_media.",
    rows: videoScansMissingManifest,
    sample: sampleScan,
    limit: input.request.limit,
  });

  const videoScansMissingReadyAssets = input.scans.filter((scan) => {
    const videoCount = cleanStringArray(scan.video_storage_urls).length;
    if (videoCount === 0) return false;
    return (readyVideoCounts.get(scan.id) ?? 0) < videoCount;
  });
  addIssue(issues, {
    code: "video_scan_missing_ready_playback_asset",
    severity: "critical",
    message:
      "Scans have durable video URLs but fewer ready playback scan_media_assets.",
    rows: videoScansMissingReadyAssets,
    sample: (row) => ({
      ...sampleScan(row),
      ready_video_asset_count: readyVideoCounts.get(row.id) ?? 0,
    }),
    limit: input.request.limit,
  });

  const scanIdsWithExpectedVideo = new Set(
    input.ingestionJobs
      .filter((job) => requiredVideoCount(job) > 0)
      .map((job) => job.scan_id),
  );
  const frameOnlyVideoSmells = input.scans.filter((scan) =>
    scanIdsWithExpectedVideo.has(scan.id) &&
    cleanStringArray(scan.video_storage_urls).length === 0 &&
    !hasCapturedVideo(scan.captured_media) &&
    capturedImageCount(scan.captured_media) >= 5
  );
  addIssue(issues, {
    code: "frame_only_video_smells",
    severity: "warning",
    message:
      "Recent scans look like sampled video frames without a durable playback video.",
    rows: frameOnlyVideoSmells,
    sample: sampleScan,
    limit: input.request.limit,
  });

  const exploreVideosMissingThumbnails = input.exploreVideoMedia.filter((
    row,
  ) => !cleanString(row.thumbnail_url));
  addIssue(issues, {
    code: "explore_video_missing_thumbnail",
    severity: "critical",
    message: "Explore video media rows are missing poster thumbnails.",
    rows: exploreVideosMissingThumbnails,
    sample: sampleExploreVideo,
    limit: input.request.limit,
  });

  const latestReconciliationRun = input.reconciliationRuns[0];
  if (
    latestReconciliationRun &&
    (latestReconciliationRun.status === "failed" ||
      latestReconciliationRun.status === "partial_failure")
  ) {
    issues.push({
      code: "latest_reconciliation_run_not_clean",
      severity: latestReconciliationRun.status === "failed"
        ? "critical"
        : "warning",
      message: "Latest scan media reconciliation run did not finish cleanly.",
      count: 1,
      sample: [sampleReconciliationRun(latestReconciliationRun)],
    });
  }

  const criticalCount =
    issues.filter((issue) => issue.severity === "critical").length;
  const warningCount =
    issues.filter((issue) => issue.severity === "warning").length;

  return {
    generated_at: input.now.toISOString(),
    status: criticalCount > 0
      ? "critical"
      : warningCount > 0
      ? "warning"
      : "ok",
    thresholds: {
      stuck_after_minutes: input.request.stuckAfterMinutes,
      stale_asset_after_minutes: input.request.staleAssetAfterMinutes,
    },
    asset_breakdown: {
      stale_capture_upload_assets: summarizeAssetsByKindRole(
        input.staleCaptureUploadAssets,
      ),
      failed_assets: summarizeAssetsByKindRole(input.failedAssets),
    },
    counts: {
      ingestion_jobs_checked: input.ingestionJobs.length,
      stale_capture_upload_assets: input.staleCaptureUploadAssets.length,
      failed_assets: input.failedAssets.length,
      recent_scans_checked: input.scans.length,
      ready_video_assets_checked: input.readyVideoAssets.length,
      explore_video_rows_checked: input.exploreVideoMedia.length,
      ready_audio_assets_checked: input.readyAudioAssets.length,
      explore_audio_rows_checked: input.exploreAudioMedia.length,
      reconciliation_runs_checked: input.reconciliationRuns.length,
      ingestion_intents_checked: input.ingestionIntents.length,
      issues: issues.length,
      critical_issues: criticalCount,
      warning_issues: warningCount,
    },
    issues,
  };
}

function summarizeAssetsByKindRole(
  rows: ScanMediaAssetHealthRow[],
): ScanMediaAssetBreakdown[] {
  const counts = new Map<string, ScanMediaAssetBreakdown>();
  for (const row of rows) {
    const kind = cleanString(row.kind) ?? "unknown";
    const role = cleanString(row.role) ?? "unknown";
    const key = `${kind}:${role}`;
    const existing = counts.get(key);
    if (existing) {
      existing.count += 1;
    } else {
      counts.set(key, { kind, role, count: 1 });
    }
  }
  return [...counts.values()].sort((lhs, rhs) =>
    lhs.kind.localeCompare(rhs.kind) ||
    lhs.role.localeCompare(rhs.role)
  );
}

function parsePositiveInteger(
  value: unknown,
  fieldName: string,
  defaultValue: number,
  maxValue: number,
): { value?: number; error?: string; status?: number } {
  if (value === undefined || value === null) return { value: defaultValue };
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return { error: `${fieldName} must be a positive number.`, status: 400 };
  }
  const integer = Math.trunc(value);
  if (integer <= 0) {
    return { error: `${fieldName} must be greater than zero.`, status: 400 };
  }
  return { value: Math.min(integer, maxValue) };
}

function addIssue<T>(
  issues: ScanMediaHealthIssue[],
  input: {
    code: string;
    severity: ScanMediaHealthSeverity;
    message: string;
    rows: T[];
    sample: (row: T) => Record<string, unknown>;
    limit: number;
  },
) {
  if (input.rows.length === 0) return;
  issues.push({
    code: input.code,
    severity: input.severity,
    message: input.message,
    count: input.rows.length,
    sample: input.rows.slice(0, input.limit).map(input.sample),
  });
}

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function cleanStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map(cleanString).filter((item): item is string => item !== null)
    : [];
}

function hasCapturedVideo(value: unknown): boolean {
  return Array.isArray(value) &&
    value.some((item) =>
      item !== null &&
      typeof item === "object" &&
      !Array.isArray(item) &&
      "video" in item
    );
}

function hasCapturedAudio(value: unknown): boolean {
  return Array.isArray(value) &&
    value.some((item) =>
      item !== null && typeof item === "object" && "audio" in item
    );
}

function capturedImageCount(value: unknown): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((item) =>
    item !== null &&
    typeof item === "object" &&
    !Array.isArray(item) &&
    "image" in item
  ).length;
}

function timeValue(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function jobKey(row: { scan_id: string; user_id: string }): string {
  return `${row.user_id}:${row.scan_id}`;
}

function sampleJob(row: ScanIngestionHealthRow): Record<string, unknown> {
  return {
    scan_id: row.scan_id,
    status: row.status,
    stage: row.stage,
    attempt_count: row.attempt_count,
    required_video_count: requiredVideoCount(row),
    lock_expires_at: row.lock_expires_at ?? null,
    retry_after: row.retry_after ?? null,
    updated_at: row.updated_at ?? null,
    last_error: row.last_error ?? null,
  };
}

function sampleIntent(
  row: ScanIngestionIntentHealthRow,
): Record<string, unknown> {
  return {
    intent_resumable: row.resumable,
    inline_media_redacted: row.inline_media_redacted,
    has_manifest_checksum: cleanString(row.manifest_checksum) !== null,
    has_payload_checksum: cleanString(row.payload_checksum) !== null,
    redacted_media_counts: row.redacted_media_counts ?? null,
    intent_updated_at: row.updated_at ?? null,
  };
}

function requiredVideoCount(row: ScanIngestionHealthRow): number {
  const mediaCounts = row.media_counts;
  if (!mediaCounts || typeof mediaCounts !== "object") return 0;
  const value = (mediaCounts as Record<string, unknown>).required_video_count;
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

function sampleAsset(row: ScanMediaAssetHealthRow): Record<string, unknown> {
  return {
    id: row.id,
    scan_id: row.scan_id,
    client_scan_id: row.client_scan_id,
    kind: row.kind,
    role: row.role,
    status: row.status,
    source: row.source,
    storage_key: row.storage_key,
    failure_reason: row.failure_reason ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function sampleScan(row: ScanMediaHealthScanRow): Record<string, unknown> {
  return {
    scan_id: row.id,
    video_storage_url_count: cleanStringArray(row.video_storage_urls).length,
    audio_storage_url_count: cleanStringArray(row.audio_storage_urls).length,
    image_storage_url_count: cleanStringArray(row.image_storage_urls).length,
    captured_media_has_video: hasCapturedVideo(row.captured_media),
    captured_media_has_audio: hasCapturedAudio(row.captured_media),
    captured_media_image_count: capturedImageCount(row.captured_media),
    timestamp: row.timestamp ?? null,
  };
}

function sampleExploreVideo(
  row: ExploreVideoMediaHealthRow,
): Record<string, unknown> {
  return {
    id: row.id,
    post_id: row.post_id,
    has_url: cleanString(row.url) !== null,
    has_thumbnail: cleanString(row.thumbnail_url) !== null,
    updated_at: row.updated_at ?? null,
  };
}

function sampleReconciliationRun(
  row: ReconciliationRunHealthRow,
): Record<string, unknown> {
  return {
    id: row.id,
    status: row.status,
    error_count: row.error_count,
    started_at: row.started_at ?? null,
    finished_at: row.finished_at ?? null,
    errors: row.errors,
  };
}
