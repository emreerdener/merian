import type { SupabaseClient } from "@supabase/supabase-js";

export interface DBScanRow {
  id: string;
  user_id: string | null;
  image_storage_urls: string[];
  video_storage_urls: string[];
  audio_storage_urls: string[];
  derived_media_urls: string[];
}

export async function fetchScanRecord(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<DBScanRow | null> {
  const { data: scan, error: fetchError } = await supabaseAdmin
    .from("scans")
    .select(
      "id, user_id, image_storage_urls, video_storage_urls, audio_storage_urls",
    )
    .eq("id", scanId)
    .maybeSingle();

  if (fetchError) {
    throw new Error(
      `Failed to fetch the canonical scan: ${fetchError.message}`,
    );
  }
  if (!scan) return null;

  const [
    { data: assets, error: assetError },
    { data: posts, error: postError },
  ] = await Promise.all([
    supabaseAdmin
      .from("scan_media_assets")
      .select("thumbnail_url")
      .eq("scan_id", scanId),
    supabaseAdmin
      .from("explore_posts")
      .select("id")
      .eq("scan_id", scanId),
  ]);
  if (assetError) {
    throw new Error(
      `Failed to fetch scan-derived media: ${assetError.message}`,
    );
  }
  if (postError) {
    throw new Error(
      `Failed to fetch Explore media owners: ${postError.message}`,
    );
  }

  const postIds = ((posts ?? []) as Array<{ id: string }>).map((row) => row.id);
  let exploreThumbnails: Array<{ thumbnail_url?: string | null }> = [];
  if (postIds.length > 0) {
    const { data, error } = await supabaseAdmin
      .from("explore_post_media")
      .select("thumbnail_url")
      .in("post_id", postIds);
    if (error) {
      throw new Error(
        `Failed to fetch Explore-derived media: ${error.message}`,
      );
    }
    exploreThumbnails = data ?? [];
  }

  const thumbnailUrls = [
    ...((assets ?? []) as Array<{ thumbnail_url?: string | null }>),
    ...exploreThumbnails,
  ].flatMap((row) => {
    const value = row.thumbnail_url?.trim();
    return value ? [value] : [];
  });
  return {
    ...(scan as Omit<DBScanRow, "derived_media_urls">),
    derived_media_urls: [...new Set(thumbnailUrls)],
  };
}

export type ScanDeletionRequestResult =
  | "accepted"
  | "already_deleted"
  | "not_found"
  | "forbidden";

export async function requestScanDeletion(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanDeletionRequestResult> {
  const { data, error } = await supabaseAdmin.rpc("request_scan_deletion", {
    p_scan_id: scanId,
    p_user_id: userId,
  });
  if (error) {
    throw new Error(`Failed to persist scan deletion: ${error.message}`);
  }
  if (
    data !== "accepted" &&
    data !== "already_deleted" &&
    data !== "not_found" &&
    data !== "forbidden"
  ) {
    throw new Error("Scan deletion returned an invalid state.");
  }
  return data;
}

export async function completeScanDeletion(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc("complete_scan_deletion", {
    p_scan_id: scanId,
    p_user_id: userId,
  });
  if (error) {
    throw new Error(`Failed to complete scan deletion: ${error.message}`);
  }
  if (data !== true) {
    throw new Error("Scan deletion lost its durable owner fence.");
  }
}
