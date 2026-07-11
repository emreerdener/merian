import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { deleteR2Object, getR2Config } from "../_shared/aws.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { refreshScanMediaAssetsBestEffort } from "../_shared/scanMediaAssets.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { moderateExploreAudioUrl } from "../_shared/audioModeration.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { runBackground } from "../_shared/edgeHandler.ts";
import { moderationLatencyBucket } from "../_shared/exploreAudioTelemetry.ts";

type TrackEvent = typeof trackPostHogEvent;

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

  const items: unknown[] = standaloneImageUrls.map(imageManifestItem);
  sanitizedVideoUrls.forEach((url, index) => {
    const thumbnailUrl = videoThumbnailUrls[index * 5] ??
      videoThumbnailUrls[0] ??
      imageUrls[0];
    items.push(videoManifestItem(url, thumbnailUrl));
  });

  return items.length > 0 ? items : null;
}

async function rollbackPromotedUrls(urls: string[]): Promise<void> {
  const r2Config = getR2Config();
  await Promise.allSettled(
    urls.map((url) =>
      deleteR2Object(url.replace("https://media.merian.app/", ""), r2Config)
    ),
  );
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchShareEligibleScan(
  scanId: string,
  userId: string,
  restoredObjectKeys: string[],
  restoredVideoObjectKeys: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ShareEligibleScanRow> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id",
    )
    .eq("id", scanId)
    .eq("user_id", userId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Scan not found.");
  }

  let row = data as ShareEligibleScanRow;

  if (row.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  if (
    (row.image_storage_urls?.length ?? 0) === 0 && restoredObjectKeys.length > 0
  ) {
    const userTier = await getTierForUser(userId, supabaseAdmin);
    const publicUrls = await promoteSafeMedia(
      {
        userId,
        r2ObjectKeys: restoredObjectKeys,
        imageBase64s: undefined,
        userTier,
        r2Config: getR2Config(),
      },
    );

    const { data: updatedRow, error: updateError } = await supabaseAdmin
      .from("scans")
      .update({ image_storage_urls: publicUrls })
      .eq("id", scanId)
      .eq("user_id", userId)
      .select(
        "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id",
      )
      .single();

    if (updateError || !updatedRow) {
      throw new Error(
        `Failed to restore shareable scan media: ${
          updateError?.message ?? "Unknown error"
        }`,
      );
    }

    row = updatedRow as ShareEligibleScanRow;
    await refreshScanMediaAssetsBestEffort(scanId, supabaseAdmin);
  }

  if (
    (row.video_storage_urls?.length ?? 0) === 0 &&
    restoredVideoObjectKeys.length > 0
  ) {
    const userTier = await getTierForUser(userId, supabaseAdmin);
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
      await rollbackPromotedUrls(videoPublicUrls);
      throw makeHttpError(503, "Restored video media could not be saved.");
    }

    const capturedMedia = buildRestoredVideoCapturedMedia(
      row,
      videoPublicUrls,
    );
    const { data: updatedRow, error: updateError } = await supabaseAdmin
      .from("scans")
      .update({
        video_storage_urls: videoPublicUrls,
        captured_media: capturedMedia,
      })
      .eq("id", scanId)
      .eq("user_id", userId)
      .select(
        "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id",
      )
      .single();

    if (updateError || !updatedRow) {
      await rollbackPromotedUrls(videoPublicUrls);
      throw new Error(
        `Failed to restore shareable scan video: ${
          updateError?.message ?? "Unknown error"
        }`,
      );
    }

    row = updatedRow as ShareEligibleScanRow;
    await refreshScanMediaAssetsBestEffort(scanId, supabaseAdmin);
  }

  if (
    (row.image_storage_urls?.length ?? 0) === 0 &&
    (row.video_storage_urls?.length ?? 0) === 0 &&
    (row.audio_storage_urls?.length ?? 0) === 0
  ) {
    throw makeHttpError(409, "This scan no longer has shareable media.");
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
      "Wait for the community to identify this request before sharing it to Explore.",
    );
  }
}

export async function markResolvedCommunityRequestPublishedToExplore(
  postId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "publish_resolved_community_request_to_explore",
    {
      target_post_id: postId,
      self_id: userId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to publish resolved community request: ${error.message}`,
    );
  }

  return typeof data === "string" ? data : null;
}

export async function upsertExplorePost(
  scan: ShareEligibleScanRow,
  userId: string,
  speciesCommonName: string | null,
  fieldNotes: string | null,
  locationSharing: string,
  mediaItems: SelectedExplorePostMediaItem[] | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<{
  id: string;
  shared_at: string;
  publication_status: string;
  media_kinds: string[];
  audio_clip_count: number;
  audible_media_count: number;
}> {
  const mediaRows = buildExplorePostMediaRows(scan, mediaItems);
  await requireApprovedAudioMedia(mediaRows, moderateExploreAudioUrl, userId);
  const sharedAt = new Date().toISOString();

  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .upsert(
      {
        scan_id: scan.id,
        user_id: userId,
        species_common_name: speciesCommonName,
        field_notes: fieldNotes,
        location_sharing: locationSharing,
        shared_at: sharedAt,
        unshared_at: null,
      },
      {
        onConflict: "scan_id",
      },
    )
    .select("id,shared_at")
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to share scan to Explore: ${error?.message ?? "Unknown error"}`,
    );
  }

  const post = data as {
    id: string;
    shared_at: string;
  };
  await replaceExplorePostMediaRows(post.id, mediaRows, supabaseAdmin);

  return {
    ...post,
    publication_status: "published",
    media_kinds: mediaRows.map((row) => row.kind),
    audio_clip_count: mediaRows.filter((row) => row.kind === "audio").length,
    audible_media_count:
      mediaRows.filter((row) =>
        row.kind === "audio" || (row.kind === "video" && row.has_audio)
      ).length,
  };
}

export async function requireApprovedAudioMedia(
  rows: ReturnType<typeof buildExplorePostMediaRows>,
  moderate: typeof moderateExploreAudioUrl = moderateExploreAudioUrl,
  telemetryUserId?: string,
  trackEvent: TrackEvent = trackPostHogEvent,
): Promise<void> {
  const audibleRows = rows.filter((row) =>
    row.kind === "audio" || (row.kind === "video" && row.has_audio)
  );

  try {
    for (const row of audibleRows) {
      const startedAt = performance.now();
      const decision = await moderate(row.url);
      if (telemetryUserId) {
        runBackground(trackEvent(
          telemetryUserId,
          "ExploreAudioModerationCompleted",
          {
            event_source: "supabase_edge",
            outcome: decision.approved ? "approved" : "rejected",
            media_kind: row.kind,
            model: decision.model,
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

async function replaceExplorePostMediaRows(
  postId: string,
  rows: ReturnType<typeof buildExplorePostMediaRows>,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error: deleteError } = await supabaseAdmin
    .from("explore_post_media")
    .delete()
    .eq("post_id", postId);

  if (deleteError) {
    throw new Error(
      `Failed to clear Explore post media: ${deleteError.message}`,
    );
  }

  const { error: insertError } = await supabaseAdmin
    .from("explore_post_media")
    .insert(rows.map((row) => ({ ...row, post_id: postId })));

  if (insertError) {
    throw new Error(
      `Failed to save Explore post media: ${insertError.message}`,
    );
  }
}

export async function replaceExplorePostHashtags(
  postId: string,
  hashtags: string[],
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error: deleteError } = await supabaseAdmin
    .from("explore_post_hashtags")
    .delete()
    .eq("post_id", postId);

  if (deleteError) {
    throw new Error(
      `Failed to clear Explore post hashtags: ${deleteError.message}`,
    );
  }

  if (hashtags.length === 0) {
    return;
  }

  const { error: insertError } = await supabaseAdmin
    .from("explore_post_hashtags")
    .insert(hashtags.map((tag) => ({ post_id: postId, tag })));

  if (insertError) {
    throw new Error(
      `Failed to save Explore post hashtags: ${insertError.message}`,
    );
  }
}
