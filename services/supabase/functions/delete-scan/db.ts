import { SupabaseClient } from "@supabase/supabase-js";

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
    .single();

  if (fetchError || !scan) {
    return null;
  }

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

export async function deleteScanRecord(
  scanId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error: deleteError } = await supabaseAdmin
    .from("scans")
    .delete()
    .eq("id", scanId);

  if (deleteError) {
    throw new Error(
      `Database deletion failed for ${scanId}: ${deleteError.message}`,
    );
  }
}
