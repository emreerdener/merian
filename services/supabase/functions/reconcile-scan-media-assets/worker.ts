import { SupabaseClient } from "@supabase/supabase-js";

import {
  deleteR2Object,
  getR2Config,
  headR2Object,
  publicR2UrlForKey,
} from "../_shared/aws.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { refreshScanMediaAssets } from "../_shared/scanMediaAssets.ts";
import {
  fetchReconciliationJobs,
  fetchReconciliationScans,
  fetchStaleCaptureUploadAssets,
  markCaptureUploadAssetDeleted,
  markCaptureUploadAssetFailed,
  markCaptureUploadAssetPromoted,
  markReconciliationJobComplete,
  markReconciliationJobFailed,
  type ReconciliationAssetRow,
  type ReconciliationJobRow,
  type ReconciliationRunInsert,
  type ReconciliationScanRow,
  recordScanMediaReconciliationRun,
  updateScanVideoMedia,
} from "./db.ts";

const DEFAULT_LIMIT = 100;
const DEFAULT_REPAIR_AFTER_MINUTES = 15;
const DEFAULT_ABANDON_AFTER_HOURS = 36;
const VIDEO_FRAME_COUNT = 5;

export interface ReconcileScanMediaAssetsOptions {
  now?: Date;
  limit?: number;
  repairAfterMinutes?: number;
  abandonAfterHours?: number;
  dryRun?: boolean;
}

export interface ReconcileScanMediaAssetsResult {
  scanned: number;
  promoted: number;
  repairedVideoScans: number;
  deletedStagingObjects: number;
  failedAssets: number;
  missingObjects: number;
  stillPending: number;
  errors: Array<{
    assetId?: string;
    storageKey?: string | null;
    reason: string;
  }>;
}

interface ReconcileDependencies {
  fetchAssets?: typeof fetchStaleCaptureUploadAssets;
  fetchScans?: typeof fetchReconciliationScans;
  fetchJobs?: typeof fetchReconciliationJobs;
  headObject?: typeof headR2Object;
  deleteObject?: typeof deleteR2Object;
  promoteMedia?: typeof promoteSafeMedia;
  markPromoted?: typeof markCaptureUploadAssetPromoted;
  markDeleted?: typeof markCaptureUploadAssetDeleted;
  markFailed?: typeof markCaptureUploadAssetFailed;
  updateScanMedia?: typeof updateScanVideoMedia;
  refreshAssets?: typeof refreshScanMediaAssets;
  markJobComplete?: typeof markReconciliationJobComplete;
  markJobFailed?: typeof markReconciliationJobFailed;
  recordRun?: typeof recordScanMediaReconciliationRun;
  r2Config?: ReturnType<typeof getR2Config>;
}

function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

function cleanUrls(urls: string[] | null | undefined): string[] {
  return (urls ?? []).map((url) => url.trim()).filter((url) => url.length > 0);
}

function fileNameFromPath(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(trimmed);
    const path = parsed.pathname.replace(/\/+$/, "");
    return path.split("/").pop() ?? null;
  } catch {
    return trimmed.replace(/\/+$/, "").split("/").pop() ?? null;
  }
}

function matchingPublicUrlForStorageKey(
  urls: string[] | null | undefined,
  storageKey: string,
): string | null {
  const fileName = fileNameFromPath(storageKey);
  if (!fileName) return null;
  return cleanUrls(urls).find((url) => fileNameFromPath(url) === fileName) ??
    null;
}

function remoteMediaReference(url: string): Record<string, string> {
  return { storage: "remoteURL", path: url };
}

function imageManifestItem(url: string): Record<string, unknown> {
  return { image: { _0: remoteMediaReference(url) } };
}

function videoManifestItem(
  url: string,
  thumbnailUrl: string | undefined,
): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    video: remoteMediaReference(url),
  };
  if (thumbnailUrl) {
    payload.thumbnail = remoteMediaReference(thumbnailUrl);
  }
  return { video: { _0: payload } };
}

function hasManifestVideo(value: unknown[] | null | undefined): boolean {
  if (!Array.isArray(value)) return false;
  return value.some((entry) =>
    entry != null &&
    typeof entry === "object" &&
    !Array.isArray(entry) &&
    Object.hasOwn(entry as Record<string, unknown>, "video")
  );
}

function capturedManifestVideoCount(
  value: unknown[] | null | undefined,
): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((entry) =>
    entry != null &&
    typeof entry === "object" &&
    !Array.isArray(entry) &&
    Object.hasOwn(entry as Record<string, unknown>, "video")
  ).length;
}

function requiredVideoCount(job: ReconciliationJobRow | undefined): number {
  const value = job?.media_counts?.required_video_count;
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

function scanSatisfiesJobMedia(
  scan: ReconciliationScanRow,
  job: ReconciliationJobRow | undefined,
): boolean {
  const requiredVideos = requiredVideoCount(job);
  if (requiredVideos <= 0) return true;
  return cleanUrls(scan.video_storage_urls).length >= requiredVideos &&
    capturedManifestVideoCount(scan.captured_media) >= requiredVideos;
}

function timeValue(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : null;
}

function jobStillOwnsPendingMedia(
  job: ReconciliationJobRow | undefined,
  now: Date,
): boolean {
  if (!job) return false;
  const nowMs = now.getTime();
  if (job.status === "processing" || job.status === "finalizing") {
    const lockExpiresAt = timeValue(job.lock_expires_at);
    return lockExpiresAt != null && lockExpiresAt > nowMs;
  }
  if (job.status === "retrying" || job.status === "failed_retryable") {
    const retryAfter = timeValue(job.retry_after);
    return retryAfter != null && retryAfter > nowMs;
  }
  return false;
}

function jobMapKey(scanId: string, userId: string): string {
  return `${userId}:${scanId}`;
}

function jobMapByScanIdAndUser(
  jobs: ReconciliationJobRow[],
): Map<string, ReconciliationJobRow> {
  return new Map(jobs.map((job) => [jobMapKey(job.scan_id, job.user_id), job]));
}

export function buildRepairedVideoCapturedMedia(
  scan: ReconciliationScanRow,
  videoUrls: string[],
): unknown[] | null {
  const sanitizedVideoUrls = cleanUrls(videoUrls);
  if (sanitizedVideoUrls.length === 0) return scan.captured_media ?? null;

  if (
    hasManifestVideo(scan.captured_media) &&
    cleanUrls(scan.video_storage_urls).length >= sanitizedVideoUrls.length
  ) {
    return scan.captured_media ?? null;
  }

  const imageUrls = cleanUrls(scan.image_storage_urls);
  const expectedVideoFrameCount = sanitizedVideoUrls.length * VIDEO_FRAME_COUNT;
  const standaloneImageCount = Math.max(
    imageUrls.length - expectedVideoFrameCount,
    0,
  );
  const standaloneImageUrls = imageUrls.slice(0, standaloneImageCount);
  const videoThumbnailUrls = imageUrls.slice(standaloneImageCount);

  const items: unknown[] = standaloneImageUrls.map(imageManifestItem);
  sanitizedVideoUrls.forEach((url, index) => {
    const thumbnailUrl = videoThumbnailUrls[index * VIDEO_FRAME_COUNT] ??
      videoThumbnailUrls[0] ??
      imageUrls[0];
    items.push(videoManifestItem(url, thumbnailUrl));
  });

  return items.length > 0 ? items : null;
}

async function objectExists(
  storageKey: string,
  r2Config: ReturnType<typeof getR2Config>,
  headObject: typeof headR2Object,
): Promise<boolean> {
  const response = await headObject(storageKey, r2Config);
  if (response.ok) return true;
  if (response.status === 404) return false;
  throw new Error(`R2 HEAD failed for ${storageKey}: ${response.status}`);
}

function emptyResult(): ReconcileScanMediaAssetsResult {
  return {
    scanned: 0,
    promoted: 0,
    repairedVideoScans: 0,
    deletedStagingObjects: 0,
    failedAssets: 0,
    missingObjects: 0,
    stillPending: 0,
    errors: [],
  };
}

function scanMapById(
  scans: ReconciliationScanRow[],
): Map<string, ReconciliationScanRow> {
  return new Map(scans.map((scan) => [scan.id, scan]));
}

async function maybeRecordRun(
  result: ReconcileScanMediaAssetsResult,
  startedAt: Date,
  finishedAt: Date,
  dryRun: boolean,
  supabaseAdmin: SupabaseClient,
  recordRun: typeof recordScanMediaReconciliationRun,
): Promise<void> {
  const row: ReconciliationRunInsert = {
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    status: dryRun
      ? "dry_run"
      : result.errors.length > 0
      ? "partial_failure"
      : "success",
    scanned_count: result.scanned,
    promoted_count: result.promoted,
    repaired_video_scan_count: result.repairedVideoScans,
    deleted_staging_object_count: result.deletedStagingObjects,
    failed_asset_count: result.failedAssets,
    missing_object_count: result.missingObjects,
    still_pending_count: result.stillPending,
    error_count: result.errors.length,
    errors: result.errors.slice(0, 50),
  };

  try {
    await recordRun(row, supabaseAdmin);
  } catch (error) {
    console.error(JSON.stringify({
      event: "scan_media_reconciliation_run_record_failed",
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
  }
}

async function reconcileExistingScanAsset(
  asset: ReconciliationAssetRow,
  scan: ReconciliationScanRow,
  result: ReconcileScanMediaAssetsResult,
  supabaseAdmin: SupabaseClient,
  options: {
    dryRun: boolean;
    r2Config: ReturnType<typeof getR2Config>;
    headObject: typeof headR2Object;
    deleteObject: typeof deleteR2Object;
    promoteMedia: typeof promoteSafeMedia;
    markPromoted: typeof markCaptureUploadAssetPromoted;
    markDeleted: typeof markCaptureUploadAssetDeleted;
    markFailed: typeof markCaptureUploadAssetFailed;
    updateScanMedia: typeof updateScanVideoMedia;
    refreshAssets: typeof refreshScanMediaAssets;
  },
): Promise<ReconciliationScanRow> {
  const storageKey = asset.storage_key?.trim() ?? "";
  if (!storageKey) {
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        "missing_storage_key",
        false,
        supabaseAdmin,
      );
    }
    result.failedAssets++;
    return scan;
  }

  if (scan.user_id !== asset.user_id) {
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        "scan_user_mismatch",
        false,
        supabaseAdmin,
      );
    }
    result.failedAssets++;
    return scan;
  }

  if (asset.kind === "audio") {
    if (!options.dryRun) {
      await options.deleteObject(storageKey, options.r2Config);
      await options.markDeleted(asset.id, scan.id, supabaseAdmin);
    }
    result.deletedStagingObjects++;
    return scan;
  }

  if (asset.kind === "image") {
    const publicUrl = matchingPublicUrlForStorageKey(
      scan.image_storage_urls,
      storageKey,
    );
    if (publicUrl) {
      if (!options.dryRun) {
        await options.markPromoted(asset.id, scan.id, publicUrl, supabaseAdmin);
      }
      result.promoted++;
      return scan;
    }

    const exists = await objectExists(
      storageKey,
      options.r2Config,
      options.headObject,
    );
    if (!exists) {
      result.missingObjects++;
    } else if (!options.dryRun) {
      await options.deleteObject(storageKey, options.r2Config);
      result.deletedStagingObjects++;
    } else {
      result.deletedStagingObjects++;
    }
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        exists ? "scan_missing_image_asset" : "image_missing_from_r2",
        exists,
        supabaseAdmin,
      );
    }
    result.failedAssets++;
    return scan;
  }

  if (asset.kind !== "video" || asset.role !== "playback") {
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        "unsupported_capture_upload_role",
        false,
        supabaseAdmin,
      );
    }
    result.failedAssets++;
    return scan;
  }

  const existingPublicUrl = matchingPublicUrlForStorageKey(
    scan.video_storage_urls,
    storageKey,
  );
  if (existingPublicUrl) {
    if (!options.dryRun) {
      await options.markPromoted(
        asset.id,
        scan.id,
        existingPublicUrl,
        supabaseAdmin,
      );
    }
    result.promoted++;
    return scan;
  }

  const exists = await objectExists(
    storageKey,
    options.r2Config,
    options.headObject,
  );
  if (!exists) {
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        "video_missing_from_r2",
        false,
        supabaseAdmin,
      );
    }
    result.missingObjects++;
    result.failedAssets++;
    return scan;
  }

  const tier = scan.inference_tier === "pro" ? "pro" : "free";
  const promotedUrls = options.dryRun
    ? [
      publicR2UrlForKey(
        `public_uploads/${tier}/${asset.user_id}/${
          fileNameFromPath(storageKey)
        }`,
      ),
    ]
    : await options.promoteMedia({
      userId: asset.user_id,
      r2ObjectKeys: [storageKey],
      imageBase64s: undefined,
      userTier: tier,
      r2Config: options.r2Config,
    });
  const promotedUrl = promotedUrls[0]?.trim();
  if (!promotedUrl) {
    throw new Error("video_promotion_returned_no_url");
  }

  const nextVideoUrls = [...cleanUrls(scan.video_storage_urls), promotedUrl];
  const nextCapturedMedia = buildRepairedVideoCapturedMedia({
    ...scan,
    video_storage_urls: nextVideoUrls,
  }, nextVideoUrls);

  if (!options.dryRun) {
    await options.updateScanMedia(
      scan.id,
      nextVideoUrls,
      nextCapturedMedia,
      supabaseAdmin,
    );
    await options.markPromoted(asset.id, scan.id, promotedUrl, supabaseAdmin);
    await options.refreshAssets(scan.id, supabaseAdmin);
  }

  result.promoted++;
  result.repairedVideoScans++;
  return {
    ...scan,
    video_storage_urls: nextVideoUrls,
    captured_media: nextCapturedMedia,
  };
}

async function reconcileAbandonedAsset(
  asset: ReconciliationAssetRow,
  result: ReconcileScanMediaAssetsResult,
  supabaseAdmin: SupabaseClient,
  options: {
    dryRun: boolean;
    r2Config: ReturnType<typeof getR2Config>;
    headObject: typeof headR2Object;
    deleteObject: typeof deleteR2Object;
    markFailed: typeof markCaptureUploadAssetFailed;
  },
): Promise<void> {
  const storageKey = asset.storage_key?.trim() ?? "";
  if (!storageKey) {
    if (!options.dryRun) {
      await options.markFailed(
        asset.id,
        "missing_storage_key",
        false,
        supabaseAdmin,
      );
    }
    result.failedAssets++;
    return;
  }

  const exists = await objectExists(
    storageKey,
    options.r2Config,
    options.headObject,
  );
  if (!exists) {
    result.missingObjects++;
  } else if (!options.dryRun) {
    await options.deleteObject(storageKey, options.r2Config);
    result.deletedStagingObjects++;
  } else {
    result.deletedStagingObjects++;
  }

  if (!options.dryRun) {
    await options.markFailed(
      asset.id,
      exists ? "scan_missing_after_ttl" : "staged_object_missing_after_ttl",
      exists,
      supabaseAdmin,
    );
  }
  result.failedAssets++;
}

export async function reconcileScanMediaAssets(
  supabaseAdmin: SupabaseClient,
  options: ReconcileScanMediaAssetsOptions = {},
  dependencies: ReconcileDependencies = {},
): Promise<ReconcileScanMediaAssetsResult> {
  const startedAt = options.now ?? new Date();
  const repairAfterMinutes = Math.max(
    options.repairAfterMinutes ?? DEFAULT_REPAIR_AFTER_MINUTES,
    1,
  );
  const abandonAfterHours = Math.max(
    options.abandonAfterHours ?? DEFAULT_ABANDON_AFTER_HOURS,
    1,
  );
  const limit = Math.max(1, Math.min(options.limit ?? DEFAULT_LIMIT, 500));
  const dryRun = options.dryRun === true;

  const fetchAssets = dependencies.fetchAssets ??
    fetchStaleCaptureUploadAssets;
  const fetchScans = dependencies.fetchScans ?? fetchReconciliationScans;
  const fetchJobs = dependencies.fetchJobs ?? fetchReconciliationJobs;
  const headObject = dependencies.headObject ?? headR2Object;
  const deleteObject = dependencies.deleteObject ?? deleteR2Object;
  const promoteMedia = dependencies.promoteMedia ?? promoteSafeMedia;
  const markPromoted = dependencies.markPromoted ??
    markCaptureUploadAssetPromoted;
  const markDeleted = dependencies.markDeleted ?? markCaptureUploadAssetDeleted;
  const markFailed = dependencies.markFailed ?? markCaptureUploadAssetFailed;
  const updateScanMedia = dependencies.updateScanMedia ?? updateScanVideoMedia;
  const refreshAssets = dependencies.refreshAssets ?? refreshScanMediaAssets;
  const markJobComplete = dependencies.markJobComplete ??
    markReconciliationJobComplete;
  const markJobFailed = dependencies.markJobFailed ??
    markReconciliationJobFailed;
  const recordRun = dependencies.recordRun ?? recordScanMediaReconciliationRun;
  const r2Config = dependencies.r2Config ?? getR2Config();

  const result = emptyResult();
  const repairCutoff = addMinutes(startedAt, -repairAfterMinutes);
  const abandonCutoff = addMinutes(startedAt, -abandonAfterHours * 60);

  const assets = await fetchAssets(
    repairCutoff.toISOString(),
    limit,
    supabaseAdmin,
  );
  result.scanned = assets.length;

  const scanIds = assets.map((asset) => asset.client_scan_id ?? "").filter((
    id,
  ) => id.length > 0);
  const scansById = scanMapById(await fetchScans(scanIds, supabaseAdmin));
  const jobsByScanIdAndUser = jobMapByScanIdAndUser(
    await fetchJobs(scanIds, supabaseAdmin),
  );

  for (const asset of assets) {
    const scan = asset.client_scan_id
      ? scansById.get(asset.client_scan_id)
      : undefined;
    const job = asset.client_scan_id
      ? jobsByScanIdAndUser.get(jobMapKey(asset.client_scan_id, asset.user_id))
      : undefined;
    const createdAt = new Date(asset.created_at);
    const isAbandoned = Number.isFinite(createdAt.getTime()) &&
      createdAt <= abandonCutoff;

    try {
      if (scan) {
        const updatedScan = await reconcileExistingScanAsset(
          asset,
          scan,
          result,
          supabaseAdmin,
          {
            dryRun,
            r2Config,
            headObject,
            deleteObject,
            promoteMedia,
            markPromoted,
            markDeleted,
            markFailed,
            updateScanMedia,
            refreshAssets,
          },
        );
        scansById.set(updatedScan.id, updatedScan);
        if (
          !dryRun &&
          job &&
          scanSatisfiesJobMedia(updatedScan, job)
        ) {
          await markJobComplete(
            updatedScan.id,
            updatedScan.user_id,
            supabaseAdmin,
          );
        }
      } else if (jobStillOwnsPendingMedia(job, startedAt)) {
        result.stillPending++;
      } else if (isAbandoned) {
        await reconcileAbandonedAsset(asset, result, supabaseAdmin, {
          dryRun,
          r2Config,
          headObject,
          deleteObject,
          markFailed,
        });
        if (!dryRun && job && asset.client_scan_id) {
          await markJobFailed(
            asset.client_scan_id,
            asset.user_id,
            "scan_missing_after_media_ttl",
            supabaseAdmin,
          );
        }
      } else {
        result.stillPending++;
      }
    } catch (error) {
      result.errors.push({
        assetId: asset.id,
        storageKey: asset.storage_key,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }

  await maybeRecordRun(
    result,
    startedAt,
    new Date(),
    dryRun,
    supabaseAdmin,
    recordRun,
  );

  console.log(JSON.stringify({
    event: "scan_media_reconciliation_complete",
    ...result,
    errors: result.errors.length,
    dry_run: dryRun,
    ts: new Date().toISOString(),
  }));

  return result;
}
