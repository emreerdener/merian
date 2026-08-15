import { SupabaseClient } from "@supabase/supabase-js";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { deleteR2ObjectIfPresent, getR2Config } from "../_shared/aws.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { refreshScanMediaAssetsBestEffort } from "../_shared/scanMediaAssets.ts";
import { getTierForUser } from "../_shared/entitlement.ts";
import {
  AudioModerationCache,
  AudioModerationQuota,
  moderateExploreAudioUrl,
} from "../_shared/audioModeration.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { logStructuredError, runBackground } from "../_shared/edgeHandler.ts";
import { moderationLatencyBucket } from "../_shared/exploreAudioTelemetry.ts";
import { createAudioSpectrogramThumbnail } from "../_shared/audioSpectrogram.ts";
import type { ExplorePostMediaSnapshotRow } from "../_shared/explorePostMedia.ts";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";
import {
  type OwnedScanRecoveryRow,
  recoverMissingOwnedScan,
} from "../_shared/scanRecovery.ts";
import {
  requireRestoredMediaLedgerBinding,
  restoredObjectKeysMissingDurableUrls,
} from "./restoredMediaValidation.ts";

type TrackEvent = typeof trackPostHogEvent;
type ModerateAudio = typeof moderateExploreAudioUrl;

export interface ApprovedAudioMediaOptions {
  moderate?: ModerateAudio;
  telemetryUserId?: string;
  trackEvent?: TrackEvent;
  cache?: AudioModerationCache;
  supabaseAdmin?: SupabaseClient;
  scanId?: string;
  quota?: AudioModerationQuota;
}

export interface ShareEligibleScanRow {
  id: string;
  user_id: string;
  geoprivacy: string;
  image_storage_urls: string[];
  video_storage_urls?: string[];
  audio_storage_urls?: string[];
  captured_media?: unknown[] | null;
  is_tombstoned: boolean;
  species_id: string | null;
  confirmed_species_id: string | null;
}

export type RestoredMediaUrlField =
  | "image_storage_urls"
  | "video_storage_urls"
  | "audio_storage_urls";

export type RestoredMediaWriteOutcome =
  | "reported_success"
  | "reported_rejected"
  | "unknown";

export type RestoredMediaPersistenceResolution =
  | {
    outcome: "committed";
    row: ShareEligibleScanRow;
    reason: string;
  }
  | {
    outcome: "rejected" | "unknown";
    row: null;
    reason: string;
  };

export interface SelectedExplorePostMediaItem {
  kind: "image" | "video" | "audio";
  source_media_id?: string;
  source_index?: number;
  thumbnail_source_index?: number;
  order_index: number;
}

function cleanMediaUrls(value: string[] | null | undefined): string[] {
  return (value ?? [])
    .map((url) => typeof url === "string" ? url.trim() : "")
    .filter((url) => url.length > 0);
}

function remoteMediaReference(
  url: string,
): { storage: "remoteURL"; path: string } {
  return { storage: "remoteURL", path: url };
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

function imageManifestItem(url: string): Record<string, unknown> {
  return { image: { _0: remoteMediaReference(url) } };
}

function isImageManifestItem(value: unknown): boolean {
  return value != null && typeof value === "object" && !Array.isArray(value) &&
    Object.hasOwn(value as Record<string, unknown>, "image");
}

function audioManifestItem(url: string): Record<string, unknown> {
  return { audio: { _0: remoteMediaReference(url) } };
}

function isStandaloneAudioManifestItem(value: unknown): boolean {
  return value != null && typeof value === "object" && !Array.isArray(value) &&
    Object.hasOwn(value as Record<string, unknown>, "audio");
}

function standaloneAudioManifestPath(value: unknown): string | null {
  if (!isStandaloneAudioManifestItem(value)) return null;
  const audio = (value as Record<string, unknown>).audio;
  if (audio == null || typeof audio !== "object" || Array.isArray(audio)) {
    return null;
  }
  const wrapper = audio as Record<string, unknown>;
  const candidate = wrapper._0 ?? wrapper;
  if (
    candidate == null || typeof candidate !== "object" ||
    Array.isArray(candidate)
  ) {
    return null;
  }
  const path = (candidate as Record<string, unknown>).path;
  return typeof path === "string" && path.trim().length > 0
    ? path.trim()
    : null;
}

export function buildRestoredAudioCapturedMedia(
  row: ShareEligibleScanRow,
  audioUrls: string[],
): unknown[] | null {
  const sanitizedAudioUrls = cleanMediaUrls(audioUrls);
  if (sanitizedAudioUrls.length === 0) return row.captured_media ?? null;
  const existingManifest = Array.isArray(row.captured_media)
    ? row.captured_media
    : [];
  if (existingManifest.length === 0) {
    return [
      ...cleanMediaUrls(row.image_storage_urls).map(imageManifestItem),
      ...sanitizedAudioUrls.map(audioManifestItem),
    ];
  }

  const existingPaths = new Set(
    existingManifest.flatMap((item) => {
      const path = standaloneAudioManifestPath(item);
      return path ? [path] : [];
    }),
  );
  return [
    ...existingManifest,
    ...sanitizedAudioUrls
      .filter((url) => !existingPaths.has(url))
      .map(audioManifestItem),
  ];
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

function isVideoManifestItem(value: unknown): boolean {
  return value != null && typeof value === "object" && !Array.isArray(value) &&
    Object.hasOwn(value as Record<string, unknown>, "video");
}

function replacingVideoManifestPath(
  value: unknown,
  path: string,
  thumbnailUrl: string | undefined,
): unknown {
  if (!isVideoManifestItem(value)) {
    return videoManifestItem(path, thumbnailUrl);
  }
  const item = value as Record<string, unknown>;
  const wrapper = item.video;
  if (
    wrapper == null || typeof wrapper !== "object" || Array.isArray(wrapper)
  ) {
    return videoManifestItem(path, thumbnailUrl);
  }
  const wrapperRecord = wrapper as Record<string, unknown>;
  const payload = wrapperRecord._0 ?? wrapperRecord;
  if (
    payload == null || typeof payload !== "object" || Array.isArray(payload)
  ) {
    return videoManifestItem(path, thumbnailUrl);
  }
  const payloadRecord = payload as Record<string, unknown>;
  const videoReference = payloadRecord.video;
  const nextVideoReference =
    videoReference != null && typeof videoReference === "object" &&
      !Array.isArray(videoReference)
      ? {
        ...(videoReference as Record<string, unknown>),
        storage: "remoteURL",
        path,
      }
      : remoteMediaReference(path);
  return {
    ...item,
    video: {
      ...wrapperRecord,
      _0: {
        ...payloadRecord,
        video: nextVideoReference,
        ...(payloadRecord.thumbnail == null && thumbnailUrl
          ? { thumbnail: remoteMediaReference(thumbnailUrl) }
          : {}),
      },
    },
  };
}

export function buildRestoredVideoCapturedMedia(
  row: ShareEligibleScanRow,
  videoUrls: string[],
): unknown[] | null {
  const sanitizedVideoUrls = cleanMediaUrls(videoUrls);
  if (sanitizedVideoUrls.length === 0) return row.captured_media ?? null;
  if (
    hasManifestVideo(row.captured_media) &&
    cleanMediaUrls(row.video_storage_urls).length >= sanitizedVideoUrls.length
  ) {
    return row.captured_media ?? null;
  }

  const imageUrls = cleanMediaUrls(row.image_storage_urls);
  const expectedVideoFrameCount = sanitizedVideoUrls.length * 5;
  const standaloneImageCount = Math.max(
    imageUrls.length - expectedVideoFrameCount,
    0,
  );
  const standaloneImageUrls = imageUrls.slice(0, standaloneImageCount);
  const videoThumbnailUrls = imageUrls.slice(standaloneImageCount);

  if (Array.isArray(row.captured_media) && row.captured_media.length > 0) {
    if (!hasManifestVideo(row.captured_media)) {
      const repairedItems: unknown[] = [];
      let imageIndex = 0;
      let insertedVideos = false;
      const appendVideos = () => {
        sanitizedVideoUrls.forEach((url, index) => {
          const thumbnailUrl = videoThumbnailUrls[index * 5] ??
            videoThumbnailUrls[0] ??
            imageUrls[0];
          repairedItems.push(videoManifestItem(url, thumbnailUrl));
        });
        insertedVideos = true;
      };
      for (const item of row.captured_media) {
        if (!isImageManifestItem(item)) {
          repairedItems.push(item);
          continue;
        }
        if (imageIndex < standaloneImageCount) {
          repairedItems.push(item);
        } else if (!insertedVideos) {
          appendVideos();
        }
        imageIndex += 1;
      }
      if (!insertedVideos) appendVideos();
      return repairedItems;
    }

    let videoIndex = 0;
    const items = row.captured_media.map((item) => {
      if (!isVideoManifestItem(item)) return item;
      const url = sanitizedVideoUrls[videoIndex];
      if (!url) return item;
      const thumbnailUrl = videoThumbnailUrls[videoIndex * 5] ??
        videoThumbnailUrls[0] ??
        imageUrls[0];
      videoIndex += 1;
      return replacingVideoManifestPath(item, url, thumbnailUrl);
    });
    for (; videoIndex < sanitizedVideoUrls.length; videoIndex += 1) {
      const thumbnailUrl = videoThumbnailUrls[videoIndex * 5] ??
        videoThumbnailUrls[0] ??
        imageUrls[0];
      items.push(
        videoManifestItem(sanitizedVideoUrls[videoIndex], thumbnailUrl),
      );
    }
    return items;
  }

  const items: unknown[] = standaloneImageUrls.map(imageManifestItem);
  sanitizedVideoUrls.forEach((url, index) => {
    const thumbnailUrl = videoThumbnailUrls[index * 5] ??
      videoThumbnailUrls[0] ??
      imageUrls[0];
    items.push(videoManifestItem(url, thumbnailUrl));
  });
  return items.length > 0 ? items : null;
}

async function rollbackPromotedUrls(
  urls: string[],
  scanId: string,
  userId: string,
  mediaField: RestoredMediaUrlField,
): Promise<void> {
  const r2Config = getR2Config();
  const results = await Promise.allSettled(
    urls.map((url) =>
      deleteR2ObjectIfPresent(
        url.replace("https://media.merian.app/", ""),
        r2Config,
      )
    ),
  );
  const failedCount =
    results.filter((result) => result.status === "rejected").length;
  if (failedCount > 0) {
    logStructuredError("explore/restored_media_rollback_partial_failure", {
      scan_id: scanId,
      user_id: userId,
      media_field: mediaField,
      failed_count: failedCount,
      total_count: urls.length,
    });
  }
}

function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
}

const COMMUNITY_IDENTIFICATION_PENDING_MESSAGE =
  "Wait for the community to identify this request before sharing it to Explore.";

const SHARE_ELIGIBLE_SCAN_SELECT =
  "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id";

async function loadShareEligibleScan(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ShareEligibleScanRow | null> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(SHARE_ELIGIBLE_SCAN_SELECT)
    .eq("id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Failed to load scan for Explore sharing: ${error.message}`,
    );
  }

  return (data as ShareEligibleScanRow | null) ?? null;
}

export function scanContainsDurableMediaUrls(
  row: ShareEligibleScanRow | null,
  mediaField: RestoredMediaUrlField,
  expectedUrls: string[],
): boolean {
  if (!row) return false;
  const durableUrls = new Set(cleanMediaUrls(row[mediaField]));
  return cleanMediaUrls(expectedUrls).every((url) => durableUrls.has(url));
}

/**
 * Resolve a restored-media update after either a normal PostgREST response or
 * a thrown/lost response. Cleanup is safe only for "rejected": that requires
 * both a returned database rejection and an exact-owner reread proving the
 * expected URLs are absent. Every other unconfirmed outcome preserves media.
 */
export async function resolveRestoredMediaPersistence(
  directRow: ShareEligibleScanRow | null,
  writeOutcome: RestoredMediaWriteOutcome,
  mediaField: RestoredMediaUrlField,
  expectedUrls: string[],
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
  writeFailure = "restored-media update was not confirmed",
): Promise<RestoredMediaPersistenceResolution> {
  if (scanContainsDurableMediaUrls(directRow, mediaField, expectedUrls)) {
    return {
      outcome: "committed",
      row: directRow!,
      reason: "direct update response contained every expected URL",
    };
  }

  let verifiedRow: ShareEligibleScanRow | null;
  try {
    verifiedRow = await loadShareEligibleScan(scanId, userId, supabaseAdmin);
  } catch (error) {
    return {
      outcome: "unknown",
      row: null,
      reason: error instanceof Error ? error.message : String(error),
    };
  }

  if (scanContainsDurableMediaUrls(verifiedRow, mediaField, expectedUrls)) {
    return {
      outcome: "committed",
      row: verifiedRow!,
      reason: "exact-owner reread contained every expected URL",
    };
  }

  if (writeOutcome === "reported_rejected") {
    return {
      outcome: "rejected",
      row: null,
      reason: writeFailure,
    };
  }

  return {
    outcome: "unknown",
    row: null,
    reason: writeFailure,
  };
}

export function restoredMediaPersistenceAllowsRollback(
  resolution: RestoredMediaPersistenceResolution,
): boolean {
  return resolution.outcome === "rejected";
}

interface PersistRestoredMediaUpdateOptions {
  scanId: string;
  userId: string;
  mediaField: RestoredMediaUrlField;
  expectedUrls: string[];
  promotedUrlsToRollback: string[];
  publicFailureMessage: string;
  supabaseAdmin: SupabaseClient;
  write: () => Promise<{
    data: ShareEligibleScanRow | null;
    error: { message: string } | null;
  }>;
}

async function persistRestoredMediaUpdate(
  options: PersistRestoredMediaUpdateOptions,
): Promise<ShareEligibleScanRow> {
  let directRow: ShareEligibleScanRow | null = null;
  let writeOutcome: RestoredMediaWriteOutcome = "unknown";
  let writeFailure = "restored-media update response was lost";

  try {
    const result = await options.write();
    directRow = result.data;
    if (result.error) {
      writeOutcome = "reported_rejected";
      writeFailure = result.error.message;
    } else {
      writeOutcome = "reported_success";
    }
  } catch (error) {
    writeFailure = error instanceof Error ? error.message : String(error);
  }

  const resolution = await resolveRestoredMediaPersistence(
    directRow,
    writeOutcome,
    options.mediaField,
    options.expectedUrls,
    options.scanId,
    options.userId,
    options.supabaseAdmin,
    writeFailure,
  );
  if (resolution.outcome === "committed") return resolution.row;

  logStructuredError("explore/restored_media_persistence_unconfirmed", {
    scan_id: options.scanId,
    user_id: options.userId,
    media_field: options.mediaField,
    persistence_outcome: resolution.outcome,
    error: resolution.reason,
  });

  if (restoredMediaPersistenceAllowsRollback(resolution)) {
    await rollbackPromotedUrls(
      options.promotedUrlsToRollback,
      options.scanId,
      options.userId,
      options.mediaField,
    );
  }

  throw publicHttpError(
    503,
    options.publicFailureMessage,
    "scan_media_restore_unavailable",
    5,
  );
}

export async function fetchShareEligibleScan(
  scanId: string,
  userId: string,
  restoredObjectKeys: string[],
  restoredVideoObjectKeys: string[],
  restoredAudioObjectKeys: string[],
  supabaseAdmin: SupabaseClient,
  recoveryScan: OwnedScanRecoveryRow | null = null,
): Promise<ShareEligibleScanRow> {
  // A share can restore image, audio, and video assets in one request. Resolve
  // the durable entitlement once for this invocation without reviving a stale,
  // process-local cache across requests.
  let userTierPromise: ReturnType<typeof getTierForUser> | null = null;
  const durableUserTier = () => {
    userTierPromise ??= getTierForUser(userId, supabaseAdmin);
    return userTierPromise;
  };
  const restoredMediaKeys = {
    restoredObjectKeys,
    restoredVideoObjectKeys,
    restoredAudioObjectKeys,
  };
  let restoredMediaBindingVerified = false;

  let row = await loadShareEligibleScan(scanId, userId, supabaseAdmin);
  if (!row && recoveryScan) {
    const hasRestoredMedia = restoredObjectKeys.length > 0 ||
      restoredVideoObjectKeys.length > 0 ||
      restoredAudioObjectKeys.length > 0;
    if (!hasRestoredMedia) {
      throw publicHttpError(
        409,
        "Restore media is required before a missing scan can be shared.",
        "scan_restore_media_required",
      );
    }
    // Staged assets are allowed to exist before their owner scan row. Prove
    // every key belongs to this exact scan, user, kind, and role before the
    // recovery RPC can create relational state. A merely nonempty attacker-
    // supplied key must never be enough to mutate the owner row.
    await requireRestoredMediaLedgerBinding(
      scanId,
      userId,
      restoredMediaKeys,
      supabaseAdmin,
    );
    restoredMediaBindingVerified = true;
    try {
      await recoverMissingOwnedScan(recoveryScan, supabaseAdmin);
    } catch (error) {
      logStructuredError("explore/scan_owner_recovery_failed", {
        scan_id: scanId,
        user_id: userId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw publicHttpError(
        503,
        "The service is temporarily unavailable.",
        "service_unavailable",
        30,
      );
    }
    row = await loadShareEligibleScan(scanId, userId, supabaseAdmin);
  }

  if (!row) {
    throw makeHttpError(404, "Scan not found.");
  }

  if (row.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  if (!restoredMediaBindingVerified) {
    await requireRestoredMediaLedgerBinding(
      scanId,
      userId,
      restoredMediaKeys,
      supabaseAdmin,
    );
  }

  if (
    (row.image_storage_urls?.length ?? 0) === 0 && restoredObjectKeys.length > 0
  ) {
    const userTier = await durableUserTier();
    const publicUrls = await promoteSafeMedia(
      {
        userId,
        r2ObjectKeys: restoredObjectKeys,
        imageBase64s: undefined,
        userTier,
        r2Config: getR2Config(),
      },
    );
    if (publicUrls.length !== restoredObjectKeys.length) {
      await rollbackPromotedUrls(
        publicUrls,
        scanId,
        userId,
        "image_storage_urls",
      );
      throw makeHttpError(503, "Restored image media could not be saved.");
    }

    row = await persistRestoredMediaUpdate({
      scanId,
      userId,
      mediaField: "image_storage_urls",
      expectedUrls: publicUrls,
      promotedUrlsToRollback: publicUrls,
      publicFailureMessage: "Restored image media could not be saved.",
      supabaseAdmin,
      write: async () => {
        const { data, error } = await supabaseAdmin
          .from("scans")
          .update({ image_storage_urls: publicUrls })
          .eq("id", scanId)
          .eq("user_id", userId)
          .select(SHARE_ELIGIBLE_SCAN_SELECT)
          .single();
        return {
          data: data as ShareEligibleScanRow | null,
          error,
        };
      },
    });
    await refreshScanMediaAssetsBestEffort(scanId, supabaseAdmin);
  }

  if (restoredAudioObjectKeys.length > 0) {
    const existingAudioUrls = cleanMediaUrls(row.audio_storage_urls);
    const audioKeysToPromote = restoredObjectKeysMissingDurableUrls(
      restoredAudioObjectKeys,
      existingAudioUrls,
      userId,
    );
    const audioPublicUrls = audioKeysToPromote.length > 0
      ? await promoteSafeMedia({
        userId,
        r2ObjectKeys: audioKeysToPromote,
        imageBase64s: undefined,
        userTier: await durableUserTier(),
        r2Config: getR2Config(),
      })
      : [];
    if (audioPublicUrls.length !== audioKeysToPromote.length) {
      await rollbackPromotedUrls(
        audioPublicUrls,
        scanId,
        userId,
        "audio_storage_urls",
      );
      throw makeHttpError(503, "Restored audio media could not be saved.");
    }

    const combinedAudioUrls = [
      ...new Set([
        ...existingAudioUrls,
        ...audioPublicUrls,
      ]),
    ];
    const capturedMedia = buildRestoredAudioCapturedMedia(
      row,
      combinedAudioUrls,
    );
    row = await persistRestoredMediaUpdate({
      scanId,
      userId,
      mediaField: "audio_storage_urls",
      expectedUrls: combinedAudioUrls,
      promotedUrlsToRollback: audioPublicUrls,
      publicFailureMessage: "Restored audio media could not be saved.",
      supabaseAdmin,
      write: async () => {
        const { data, error } = await supabaseAdmin
          .from("scans")
          .update({
            audio_storage_urls: combinedAudioUrls,
            captured_media: capturedMedia,
          })
          .eq("id", scanId)
          .eq("user_id", userId)
          .select(SHARE_ELIGIBLE_SCAN_SELECT)
          .single();
        return {
          data: data as ShareEligibleScanRow | null,
          error,
        };
      },
    });
    await refreshScanMediaAssetsBestEffort(scanId, supabaseAdmin);
  }

  if (
    (row.video_storage_urls?.length ?? 0) === 0 &&
    restoredVideoObjectKeys.length > 0
  ) {
    const userTier = await durableUserTier();
    const videoPublicUrls = await promoteSafeMedia(
      {
        userId,
        r2ObjectKeys: restoredVideoObjectKeys,
        imageBase64s: undefined,
        userTier,
        r2Config: getR2Config(),
      },
    );
    if (videoPublicUrls.length !== restoredVideoObjectKeys.length) {
      await rollbackPromotedUrls(
        videoPublicUrls,
        scanId,
        userId,
        "video_storage_urls",
      );
      throw makeHttpError(503, "Restored video media could not be saved.");
    }

    const capturedMedia = buildRestoredVideoCapturedMedia(
      row,
      videoPublicUrls,
    );
    row = await persistRestoredMediaUpdate({
      scanId,
      userId,
      mediaField: "video_storage_urls",
      expectedUrls: videoPublicUrls,
      promotedUrlsToRollback: videoPublicUrls,
      publicFailureMessage: "Restored video media could not be saved.",
      supabaseAdmin,
      write: async () => {
        const { data, error } = await supabaseAdmin
          .from("scans")
          .update({
            video_storage_urls: videoPublicUrls,
            captured_media: capturedMedia,
          })
          .eq("id", scanId)
          .eq("user_id", userId)
          .select(SHARE_ELIGIBLE_SCAN_SELECT)
          .single();
        return {
          data: data as ShareEligibleScanRow | null,
          error,
        };
      },
    });
    await refreshScanMediaAssetsBestEffort(scanId, supabaseAdmin);
  }

  if (
    (row.image_storage_urls?.length ?? 0) === 0 &&
    (row.video_storage_urls?.length ?? 0) === 0 &&
    (row.audio_storage_urls?.length ?? 0) === 0
  ) {
    throw makeHttpError(409, "This scan no longer has shareable media.");
  }

  if (row.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  if (row.confirmed_species_id == null && row.species_id == null) {
    throw makeHttpError(409, "Only biological scans can be shared to Explore.");
  }

  return row;
}

export async function assertCommunityRequestCanPublishToExplore(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin
    .from("explore_community_requests")
    .select("id,status")
    .eq("scan_id", scanId)
    .eq("requested_by", userId)
    .neq("status", "withdrawn")
    .order("requested_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to inspect community request: ${error.message}`);
  }

  const row = data as { status?: string } | null;
  if (row?.status === "needs_id") {
    throw makeHttpError(
      409,
      COMMUNITY_IDENTIFICATION_PENDING_MESSAGE,
    );
  }
}

interface AtomicExplorePublicationResult {
  post_id: string;
  shared_at: string;
  location_sharing: "open" | "obscured" | "private";
  publication_status: "published";
}

function isAtomicExplorePublicationResult(
  value: unknown,
): value is AtomicExplorePublicationResult {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Record<string, unknown>;
  return typeof row.post_id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(row.post_id) &&
    typeof row.shared_at === "string" &&
    row.shared_at.length > 0 &&
    Number.isFinite(Date.parse(row.shared_at)) &&
    (
      row.location_sharing === "open" ||
      row.location_sharing === "obscured" ||
      row.location_sharing === "private"
    ) &&
    row.publication_status === "published";
}

export async function publishExplorePostAtomically(
  scan: ShareEligibleScanRow,
  userId: string,
  speciesCommonName: string | null,
  fieldNotes: string | null,
  requestedLocationSharing: string | null,
  mediaItems: SelectedExplorePostMediaItem[] | undefined,
  hashtags: string[],
  supabaseAdmin: SupabaseClient,
  moderationQuota: AudioModerationQuota,
): Promise<{
  id: string;
  shared_at: string;
  location_sharing: "open" | "obscured" | "private";
  publication_status: "published";
  media_kinds: string[];
  audio_clip_count: number;
  audible_media_count: number;
}> {
  let mediaRows = buildExplorePostMediaRows(scan, mediaItems);
  mediaRows = await prepareExplorePostMediaForPublication(
    scan.id,
    userId,
    mediaRows,
    supabaseAdmin,
    moderationQuota,
  );
  const { data, error } = await supabaseAdmin.rpc(
    "publish_scan_to_explore_atomically",
    {
      p_scan_id: scan.id,
      p_user_id: userId,
      p_species_common_name: speciesCommonName,
      p_field_notes: fieldNotes,
      p_location_sharing: requestedLocationSharing,
      p_media_rows: mediaRows,
      p_hashtags: hashtags,
    },
  );

  if (
    error?.code === "P0001" &&
    error.message === COMMUNITY_IDENTIFICATION_PENDING_MESSAGE
  ) {
    throw makeHttpError(409, COMMUNITY_IDENTIFICATION_PENDING_MESSAGE);
  }

  if (error || !isAtomicExplorePublicationResult(data)) {
    throw new Error(
      `Failed to publish scan to Explore atomically: ${
        error?.message ?? "Invalid database response"
      }`,
    );
  }

  return {
    id: data.post_id,
    shared_at: data.shared_at,
    location_sharing: data.location_sharing,
    publication_status: data.publication_status,
    media_kinds: mediaRows.map((row) => row.kind),
    audio_clip_count: mediaRows.filter((row) => row.kind === "audio").length,
    audible_media_count:
      mediaRows.filter((row) =>
        row.kind === "audio" || (row.kind === "video" && row.has_audio)
      ).length,
  };
}

export async function attachAudioSpectrogramThumbnails(
  scanId: string,
  rows: ExplorePostMediaSnapshotRow[],
  supabaseAdmin: SupabaseClient,
  createThumbnail: typeof createAudioSpectrogramThumbnail =
    createAudioSpectrogramThumbnail,
): Promise<ExplorePostMediaSnapshotRow[]> {
  const output: ExplorePostMediaSnapshotRow[] = [];
  for (const row of rows) {
    if (row.kind !== "audio" || row.thumbnail_url.trim().length > 0) {
      output.push(row);
      continue;
    }

    try {
      const thumbnailUrl = await createThumbnail(row.url);
      if (!thumbnailUrl) {
        output.push(row);
        continue;
      }

      const { error } = await supabaseAdmin
        .from("scan_media_assets")
        .update({ thumbnail_url: thumbnailUrl })
        .eq("scan_id", scanId)
        .eq("kind", "audio")
        .eq("url", row.url);
      if (error) {
        console.warn(JSON.stringify({
          event: "explore_audio_spectrogram_asset_update_failed",
          scan_id: scanId,
          error: error.message,
        }));
      }
      output.push({ ...row, thumbnail_url: thumbnailUrl });
    } catch (error) {
      console.warn(JSON.stringify({
        event: "explore_audio_spectrogram_generation_failed",
        scan_id: scanId,
        error: error instanceof Error ? error.message : String(error),
      }));
      output.push(row);
    }
  }
  return output;
}

export async function requireApprovedAudioMedia(
  rows: ReturnType<typeof buildExplorePostMediaRows>,
  options: ApprovedAudioMediaOptions = {},
): Promise<void> {
  const moderate = options.moderate ?? moderateExploreAudioUrl;
  const trackEvent = options.trackEvent ?? trackPostHogEvent;
  const { telemetryUserId, cache, supabaseAdmin, scanId, quota } = options;
  const audibleRows = rows.filter((row) =>
    row.kind === "audio" || (row.kind === "video" && row.has_audio)
  );

  try {
    for (const row of audibleRows) {
      const startedAt = performance.now();
      const decision = await moderate(
        row.url,
        cache,
        fetch,
        undefined,
        quota,
        scanId,
      );
      if (supabaseAdmin && !decision.cacheHit && decision.usage) {
        recordAIUsageBestEffort(supabaseAdmin, {
          operation: "explore_audio_moderation",
          model: decision.model,
          usage: decision.usage,
          inputModality: row.kind === "video" ? "video" : "audio",
          outcome: decision.approved ? "success" : "refusal",
          userId: telemetryUserId ?? null,
          scanId: scanId ?? null,
          sourceType: decision.checksumSha256 ? "media_checksum" : null,
          sourceId: decision.checksumSha256
            ? uuidFromSha256(decision.checksumSha256)
            : null,
        });
      }
      if (telemetryUserId) {
        runBackground(trackEvent(
          telemetryUserId,
          "ExploreAudioModerationCompleted",
          {
            event_source: "supabase_edge",
            outcome: decision.approved ? "approved" : "rejected",
            media_kind: row.kind,
            model: decision.model,
            policy_version: decision.policyVersion,
            cache_hit: decision.cacheHit ?? false,
            latency_bucket: moderationLatencyBucket(
              performance.now() - startedAt,
            ),
          },
        ));
      }
      if (!decision.approved) {
        throw makeHttpError(
          422,
          "This audio cannot be shared because it did not pass moderation.",
        );
      }
    }
  } catch (error) {
    if (
      telemetryUserId &&
      !(error && typeof error === "object" && "status" in error)
    ) {
      runBackground(trackEvent(
        telemetryUserId,
        "ExploreAudioModerationCompleted",
        {
          event_source: "supabase_edge",
          outcome: "error",
        },
      ));
    }
    if (error && typeof error === "object" && "status" in error) throw error;
    throw makeHttpError(
      503,
      "Audio moderation is temporarily unavailable. Nothing was shared.",
    );
  }
}

export async function prepareExplorePostMediaForPublication(
  scanId: string,
  userId: string,
  rows: ExplorePostMediaSnapshotRow[],
  supabaseAdmin: SupabaseClient,
  quota: AudioModerationQuota,
): Promise<ExplorePostMediaSnapshotRow[]> {
  await requireApprovedAudioMedia(rows, {
    telemetryUserId: userId,
    cache: exploreAudioModerationCache(supabaseAdmin),
    supabaseAdmin,
    scanId,
    quota,
  });
  return await attachAudioSpectrogramThumbnails(
    scanId,
    rows,
    supabaseAdmin,
  );
}

function uuidFromSha256(checksum: string): string | null {
  const hex = checksum.toLowerCase().replace(/[^0-9a-f]/g, "").slice(0, 32);
  if (hex.length !== 32) return null;
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20, 32)}`;
}

export function exploreAudioModerationCache(
  supabaseAdmin: SupabaseClient,
): AudioModerationCache {
  return {
    async lookup(checksumSha256, policyVersion, model) {
      const { data, error } = await supabaseAdmin
        .from("explore_audio_moderation_attestations")
        .select("approved")
        .eq("checksum_sha256", checksumSha256)
        .eq("policy_version", policyVersion)
        .eq("model", model)
        .maybeSingle();
      if (error) {
        throw new Error(
          `Audio moderation cache lookup failed: ${error.message}`,
        );
      }
      if (!data) return null;
      return {
        approved: Boolean((data as { approved: boolean }).approved),
        model,
        policyVersion,
      };
    },
    async store(input) {
      const { error } = await supabaseAdmin
        .from("explore_audio_moderation_attestations")
        .upsert({
          checksum_sha256: input.checksumSha256,
          policy_version: input.policyVersion,
          model: input.model,
          approved: input.approved,
          media_type: input.mediaType,
          byte_size: input.byteSize,
        }, {
          onConflict: "checksum_sha256,policy_version,model",
          ignoreDuplicates: true,
        });
      if (error) {
        throw new Error(
          `Audio moderation cache store failed: ${error.message}`,
        );
      }
    },
  };
}
