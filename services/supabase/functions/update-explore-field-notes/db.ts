import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";

export interface ExistingExplorePostMediaSelection {
  kind: "image" | "video";
  source_media_id?: string;
  url?: string;
  thumbnail_url?: string | null;
  order_index: number;
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function updateExploreFieldNotes(
  postId: string,
  userId: string,
  fieldNotes: string | null,
  hashtags: string[] | undefined,
  speciesCommonName: string | null | undefined,
  locationSharing: string | undefined,
  mediaItems: ExistingExplorePostMediaSelection[] | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<{
  id: string;
  field_notes: string | null;
  species_common_name: string | null;
  location_sharing: string;
  hashtags?: string[];
}> {
  const updates: {
    field_notes: string | null;
    species_common_name?: string | null;
    location_sharing?: string;
  } = {
    field_notes: fieldNotes,
  };
  if (speciesCommonName !== undefined) {
    updates.species_common_name = speciesCommonName;
  }
  if (locationSharing !== undefined) {
    updates.location_sharing = locationSharing;
  }

  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .update(updates)
    .eq("id", postId)
    .eq("user_id", userId)
    .is("unshared_at", null)
    .select("id,scan_id,field_notes,species_common_name,location_sharing")
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore post not found.");
  }

  if (hashtags !== undefined) {
    const { error: deleteError } = await supabaseAdmin
      .from("explore_post_hashtags")
      .delete()
      .eq("post_id", postId);

    if (deleteError) {
      throw new Error(
        `Failed to clear Explore post hashtags: ${deleteError.message}`,
      );
    }

    if (hashtags.length > 0) {
      const { error: insertError } = await supabaseAdmin
        .from("explore_post_hashtags")
        .insert(hashtags.map((tag) => ({ post_id: postId, tag })));

      if (insertError) {
        throw new Error(
          `Failed to save Explore post hashtags: ${insertError.message}`,
        );
      }
    }
  }

  if (mediaItems !== undefined) {
    await replaceExplorePostMedia(
      postId,
      userId,
      (data as { scan_id: string }).scan_id,
      mediaItems,
      supabaseAdmin,
    );
  }

  return {
    ...(data as {
      id: string;
      scan_id: string;
      field_notes: string | null;
      species_common_name: string | null;
      location_sharing: string;
    }),
    hashtags,
  };
}

async function replaceExplorePostMedia(
  postId: string,
  userId: string,
  scanId: string,
  mediaItems: ExistingExplorePostMediaSelection[],
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (mediaItems.length === 0) {
    throw makeHttpError(400, "media_items must include at least one item.");
  }

  const rows = mediaItems.some((item) => item.source_media_id)
    ? await mediaRowsFromSourceIds(
      postId,
      userId,
      scanId,
      mediaItems,
      supabaseAdmin,
    )
    : await mediaRowsFromExistingPost(postId, mediaItems, supabaseAdmin);

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
    .insert(rows);

  if (insertError) {
    throw new Error(
      `Failed to save Explore post media: ${insertError.message}`,
    );
  }
}

async function mediaRowsFromExistingPost(
  postId: string,
  mediaItems: ExistingExplorePostMediaSelection[],
  supabaseAdmin: SupabaseClient,
): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_media")
    .select("kind,url,thumbnail_url,duration_seconds,has_audio")
    .eq("post_id", postId);

  if (error) {
    throw new Error(`Failed to load Explore post media: ${error.message}`);
  }

  const existing = new Map<string, {
    kind: "image" | "video";
    url: string;
    thumbnail_url: string | null;
    duration_seconds: number | null;
    has_audio: boolean;
  }>();

  for (const row of data ?? []) {
    const typed = row as {
      kind: "image" | "video";
      url: string;
      thumbnail_url: string | null;
      duration_seconds: number | null;
      has_audio: boolean;
    };
    existing.set(`${typed.kind}:${typed.url}`, typed);
  }

  const rows = mediaItems
    .slice()
    .sort((lhs, rhs) => lhs.order_index - rhs.order_index)
    .map((item, offset) => {
      if (!item.url) {
        throw makeHttpError(400, "Selected media requires a URL.");
      }
      const match = existing.get(`${item.kind}:${item.url}`);
      if (!match) {
        throw makeHttpError(
          400,
          "Selected media does not belong to this Explore post.",
        );
      }
      if (item.kind === "video" && !nonEmptyString(match.thumbnail_url)) {
        throw makeHttpError(409, "Video thumbnail unavailable.");
      }

      return {
        post_id: postId,
        kind: match.kind,
        url: match.url,
        thumbnail_url: match.kind === "video"
          ? match.thumbnail_url
          : match.thumbnail_url ?? match.url,
        order_index: offset,
        duration_seconds: match.duration_seconds,
        has_audio: match.has_audio,
      };
    });

  return rows;
}

async function mediaRowsFromSourceIds(
  postId: string,
  userId: string,
  scanId: string,
  mediaItems: ExistingExplorePostMediaSelection[],
  supabaseAdmin: SupabaseClient,
): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,image_storage_urls,video_storage_urls,captured_media,is_tombstoned",
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
  const scan = data as {
    id: string;
    image_storage_urls: string[] | null;
    video_storage_urls: string[] | null;
    captured_media: unknown[] | null;
    is_tombstoned: boolean;
  };
  if (scan.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  return buildExplorePostMediaRows(scan, mediaItems)
    .map((row) => ({ ...row, post_id: postId }));
}

function nonEmptyString(value: string | null | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}
