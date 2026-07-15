import { SupabaseClient } from "@supabase/supabase-js";
import {
  buildComposerMediaSources,
  ExploreComposerMediaSource,
} from "../_shared/exploreComposerMedia.ts";
import {
  fetchScanMediaAssetsBestEffort,
  ScanMediaAssetRow,
} from "../_shared/scanMediaAssets.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

interface ComposerScanRow {
  id: string;
  user_id: string;
  image_storage_urls: string[] | null;
  video_storage_urls: string[] | null;
  audio_storage_urls: string[] | null;
  captured_media: unknown[] | null;
  media_assets?: ScanMediaAssetRow[] | null;
  is_tombstoned: boolean;
}

interface ComposerPostRow {
  id: string;
  scan_id: string;
  user_id: string;
  unshared_at?: string | null;
}

interface PostMediaRow {
  kind: "image" | "video" | "audio";
  url: string;
  thumbnail_url?: string | null;
  order_index: number;
}

export async function fetchExploreComposerMedia(
  userId: string,
  input: { scanId?: string; postId?: string },
  supabaseAdmin: SupabaseClient,
): Promise<{
  scan_id: string;
  post_id: string | null;
  media_items: ExploreComposerMediaSource[];
}> {
  const post = input.postId
    ? await fetchOwnedPost(input.postId, userId, supabaseAdmin)
    : null;
  const scanId = post?.scan_id ?? input.scanId;
  if (!scanId) {
    throw makeHttpError(400, "scan_id or post_id is required.");
  }

  const scan = await fetchOwnedScan(scanId, userId, supabaseAdmin);
  const selectedMedia = post
    ? await selectedSourceMediaForPost(post.id, scan, supabaseAdmin)
    : {
      orderBySourceId: new Map<string, number>(),
      thumbnailBySourceId: new Map<string, string>(),
    };

  const mediaItems = buildComposerMediaSources(
    scan,
    selectedMedia.orderBySourceId,
  )
    .map((item) => {
      const selectedThumbnail = selectedMedia.thumbnailBySourceId.get(
        item.source_media_id,
      );
      return selectedThumbnail
        ? { ...item, thumbnail_url: selectedThumbnail }
        : item;
    })
    .map((item) => post ? item : { ...item, is_selected: true })
    .sort((lhs, rhs) => {
      const lhsSelection = lhs.selection_order_index;
      const rhsSelection = rhs.selection_order_index;
      if (lhsSelection != null && rhsSelection != null) {
        return lhsSelection - rhsSelection;
      }
      if (lhsSelection != null) return -1;
      if (rhsSelection != null) return 1;
      return lhs.order_index - rhs.order_index;
    });

  if (mediaItems.length === 0) {
    throw makeHttpError(409, "This scan no longer has shareable media.");
  }

  return {
    scan_id: scan.id,
    post_id: post?.id ?? null,
    media_items: mediaItems,
  };
}

async function fetchOwnedPost(
  postId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ComposerPostRow> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select("id,scan_id,user_id,unshared_at")
    .eq("id", postId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load Explore post: ${error.message}`);
  }
  if (!data || (data as ComposerPostRow).unshared_at != null) {
    throw makeHttpError(404, "Explore post not found.");
  }

  return data as ComposerPostRow;
}

async function fetchOwnedScan(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ComposerScanRow> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,image_storage_urls,video_storage_urls,audio_storage_urls,captured_media,is_tombstoned",
    )
    .eq("id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load scan media: ${error.message}`);
  }
  if (!data) {
    throw makeHttpError(404, "Scan not found.");
  }

  const scan = data as ComposerScanRow;
  if (scan.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  return {
    ...scan,
    media_assets: await fetchScanMediaAssetsBestEffort(scan.id, supabaseAdmin),
  };
}

async function selectedSourceMediaForPost(
  postId: string,
  scan: ComposerScanRow,
  supabaseAdmin: SupabaseClient,
): Promise<{
  orderBySourceId: Map<string, number>;
  thumbnailBySourceId: Map<string, string>;
}> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_media")
    .select("kind,url,thumbnail_url,order_index")
    .eq("post_id", postId)
    .order("order_index", { ascending: true });

  if (error) {
    throw new Error(`Failed to load Explore post media: ${error.message}`);
  }

  const orderBySourceId = new Map<string, number>();
  const thumbnailBySourceId = new Map<string, string>();
  const mediaSources = buildComposerMediaSources(scan);

  for (const row of (data ?? []) as PostMediaRow[]) {
    const source = mediaSources.find((candidate) =>
      candidate.kind === row.kind && candidate.url === row.url
    );
    if (!source) continue;
    const sourceMediaId = source.source_media_id;
    orderBySourceId.set(sourceMediaId, row.order_index);
    if (row.thumbnail_url?.trim()) {
      thumbnailBySourceId.set(sourceMediaId, row.thumbnail_url.trim());
    }
  }

  return { orderBySourceId, thumbnailBySourceId };
}
