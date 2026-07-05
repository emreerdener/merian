import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getR2Config } from "../_shared/aws.ts";
import {
  buildComposerMediaSources,
  cleanMediaUrls,
  parseSourceMediaId,
} from "../_shared/exploreComposerMedia.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { getTierForUser } from "../_shared/tierCache.ts";

export interface ShareEligibleScanRow {
  id: string;
  user_id: string;
  geoprivacy: string;
  image_storage_urls: string[];
  video_storage_urls?: string[];
  captured_media?: unknown[] | null;
  is_tombstoned: boolean;
  species_id: string | null;
  confirmed_species_id: string | null;
}

export interface SelectedExplorePostMediaItem {
  kind: "image" | "video";
  source_media_id?: string;
  source_index?: number;
  thumbnail_source_index?: number;
  order_index: number;
}

interface ExplorePostMediaInsertRow {
  kind: "image" | "video";
  url: string;
  thumbnail_url: string;
  order_index: number;
  duration_seconds: number | null;
  has_audio: boolean;
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
  supabaseAdmin: SupabaseClient,
): Promise<ShareEligibleScanRow> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id",
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
        "id,user_id,geoprivacy,image_storage_urls,video_storage_urls,captured_media,is_tombstoned,species_id,confirmed_species_id",
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
  }

  if (
    (row.image_storage_urls?.length ?? 0) === 0 &&
    (row.video_storage_urls?.length ?? 0) === 0
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
): Promise<{ id: string; shared_at: string }> {
  const mediaRows = buildExplorePostMediaRows(scan, mediaItems);

  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .upsert(
      {
        scan_id: scan.id,
        user_id: userId,
        species_common_name: speciesCommonName,
        field_notes: fieldNotes,
        location_sharing: locationSharing,
        shared_at: new Date().toISOString(),
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

  const post = data as { id: string; shared_at: string };
  await replaceExplorePostMediaRows(post.id, mediaRows, supabaseAdmin);

  return post;
}

export function buildExplorePostMediaRows(
  scan: ShareEligibleScanRow,
  mediaItems: SelectedExplorePostMediaItem[] | undefined,
): ExplorePostMediaInsertRow[] {
  if (mediaItems !== undefined && mediaItems.length === 0) {
    throw makeHttpError(400, "media_items must include at least one item.");
  }

  const composerSources = buildComposerMediaSources(scan);
  const selectedSources = mediaItems === undefined
    ? composerSources
    : mediaItems
      .slice()
      .sort((lhs, rhs) => lhs.order_index - rhs.order_index)
      .map((item) => sourceForSelection(item, scan, composerSources));

  const rows = selectedSources.map((source, offset) => {
    if (source.kind === "video" && source.thumbnail_url === source.url) {
      throw makeHttpError(409, "Video thumbnail unavailable.");
    }

    return {
      kind: source.kind,
      url: source.url,
      thumbnail_url: source.thumbnail_url,
      order_index: offset,
      duration_seconds: null,
      has_audio: source.kind === "video",
    };
  });

  if (rows.length === 0) {
    throw makeHttpError(409, "This scan no longer has shareable media.");
  }

  return rows;
}

function sourceForSelection(
  item: SelectedExplorePostMediaItem,
  scan: ShareEligibleScanRow,
  composerSources: ReturnType<typeof buildComposerMediaSources>,
): {
  kind: "image" | "video";
  url: string;
  thumbnail_url: string;
} {
  if (item.source_media_id) {
    const parsed = parseSourceMediaId(item.source_media_id);
    if (!parsed || parsed.scanId !== scan.id.toLowerCase()) {
      throw makeHttpError(400, "Selected media does not belong to this scan.");
    }
    if (parsed.kind !== item.kind) {
      throw makeHttpError(
        400,
        "Selected media kind does not match its source.",
      );
    }

    const source = composerSources.find((candidate) =>
      candidate.source_media_id === item.source_media_id &&
      candidate.kind === item.kind
    );
    if (!source) {
      throw makeHttpError(
        400,
        `Selected ${item.kind} media does not belong to this scan.`,
      );
    }

    return source;
  }

  const imageUrls = cleanMediaUrls(scan.image_storage_urls);
  const videoUrls = cleanMediaUrls(scan.video_storage_urls ?? []);
  const source = sourceIndexForSelection(item);
  if (item.kind === "image") {
    const url = imageUrls[source.index];
    if (!url) {
      throw makeHttpError(
        400,
        "Selected image media does not belong to this scan.",
      );
    }

    return {
      kind: "image",
      url,
      thumbnail_url: url,
    };
  }

  const url = videoUrls[source.index];
  if (!url) {
    throw makeHttpError(
      400,
      "Selected video media does not belong to this scan.",
    );
  }

  const thumbnailIndex = item.thumbnail_source_index ?? Math.min(
    source.index,
    imageUrls.length - 1,
  );
  const thumbnailUrl = imageUrls[thumbnailIndex];
  if (!thumbnailUrl) {
    throw makeHttpError(409, "Video thumbnail unavailable.");
  }

  return {
    kind: "video",
    url,
    thumbnail_url: thumbnailUrl,
  };
}

async function replaceExplorePostMediaRows(
  postId: string,
  rows: ExplorePostMediaInsertRow[],
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

function sourceIndexForSelection(
  item: SelectedExplorePostMediaItem,
): { index: number } {
  if (item.source_index == null) {
    throw makeHttpError(400, "Selected media requires a source.");
  }

  return { index: item.source_index };
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
