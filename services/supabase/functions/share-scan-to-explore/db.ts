import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getR2Config } from "../_shared/aws.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { getTierForUser } from "../_shared/tierCache.ts";

export interface ShareEligibleScanRow {
  id: string;
  user_id: string;
  geoprivacy: string;
  image_storage_urls: string[];
  is_tombstoned: boolean;
  species_id: string | null;
  confirmed_species_id: string | null;
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
      "id,user_id,geoprivacy,image_storage_urls,is_tombstoned,species_id,confirmed_species_id",
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
        "id,user_id,geoprivacy,image_storage_urls,is_tombstoned,species_id,confirmed_species_id",
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

  if ((row.image_storage_urls?.length ?? 0) === 0) {
    throw makeHttpError(409, "This scan no longer has shareable image media.");
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
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_community_requests")
    .update({ explore_published_at: new Date().toISOString() })
    .eq("post_id", postId)
    .eq("requested_by", userId)
    .eq("status", "resolved")
    .is("explore_published_at", null);

  if (error) {
    throw new Error(
      `Failed to mark community request as Explore-published: ${error.message}`,
    );
  }
}

export async function upsertExplorePost(
  scanId: string,
  userId: string,
  speciesCommonName: string | null,
  fieldNotes: string | null,
  locationSharing: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; shared_at: string }> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .upsert(
      {
        scan_id: scanId,
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

  return data as { id: string; shared_at: string };
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
