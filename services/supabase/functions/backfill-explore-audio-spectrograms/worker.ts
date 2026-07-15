import type { SupabaseClient } from "@supabase/supabase-js";
import { createAudioSpectrogramThumbnail } from "../_shared/audioSpectrogram.ts";

type AudioMediaRow = {
  id: string;
  post_id: string;
  url: string;
  thumbnail_url?: string | null;
};

export type AudioSpectrogramBackfillResult = {
  scanned_count: number;
  generated_count: number;
  unsupported_count: number;
  failed_count: number;
  errors: Array<{ media_id: string; error: string }>;
};

export async function backfillExploreAudioSpectrograms(
  supabaseAdmin: SupabaseClient,
  limit = 50,
  createThumbnail: typeof createAudioSpectrogramThumbnail =
    createAudioSpectrogramThumbnail,
): Promise<AudioSpectrogramBackfillResult> {
  const boundedLimit = Math.max(1, Math.min(Math.trunc(limit), 200));
  const { data, error } = await supabaseAdmin
    .from("explore_post_media")
    .select("id,post_id,url,thumbnail_url")
    .eq("kind", "audio")
    .ilike("url", "%.wav")
    .or("thumbnail_url.is.null,thumbnail_url.eq.")
    .order("created_at", { ascending: true })
    .limit(boundedLimit);
  if (error) {
    throw new Error(
      `Failed to fetch audio spectrogram candidates: ${error.message}`,
    );
  }

  const mediaRows = (data ?? []) as AudioMediaRow[];
  const postIds = [...new Set(mediaRows.map((row) => row.post_id))];
  const scanIdByPostId = new Map<string, string>();
  if (postIds.length > 0) {
    const { data: posts, error: postError } = await supabaseAdmin
      .from("explore_posts")
      .select("id,scan_id")
      .in("id", postIds);
    if (postError) {
      throw new Error(
        `Failed to fetch audio spectrogram owners: ${postError.message}`,
      );
    }
    for (
      const post of (posts ?? []) as Array<{ id: string; scan_id: string }>
    ) {
      scanIdByPostId.set(post.id, post.scan_id);
    }
  }

  const result: AudioSpectrogramBackfillResult = {
    scanned_count: mediaRows.length,
    generated_count: 0,
    unsupported_count: 0,
    failed_count: 0,
    errors: [],
  };

  for (const media of mediaRows) {
    try {
      const thumbnailUrl = await createThumbnail(media.url);
      if (!thumbnailUrl) {
        result.unsupported_count += 1;
        continue;
      }
      const { error: mediaError } = await supabaseAdmin
        .from("explore_post_media")
        .update({ thumbnail_url: thumbnailUrl })
        .eq("id", media.id)
        .eq("url", media.url);
      if (mediaError) throw new Error(mediaError.message);

      const scanId = scanIdByPostId.get(media.post_id);
      if (scanId) {
        const { error: assetError } = await supabaseAdmin
          .from("scan_media_assets")
          .update({ thumbnail_url: thumbnailUrl })
          .eq("scan_id", scanId)
          .eq("kind", "audio")
          .eq("url", media.url);
        if (assetError) {
          console.warn(JSON.stringify({
            event: "audio_spectrogram_backfill_asset_update_failed",
            media_id: media.id,
            error: assetError.message,
          }));
        }
      }
      result.generated_count += 1;
    } catch (backfillError) {
      result.failed_count += 1;
      result.errors.push({
        media_id: media.id,
        error: backfillError instanceof Error
          ? backfillError.message
          : String(backfillError),
      });
    }
  }
  return result;
}
