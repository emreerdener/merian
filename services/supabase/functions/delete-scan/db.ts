import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface DBScanRow {
  id: string;
  user_id: string;
  image_storage_urls: string[];
  video_storage_urls: string[];
}

export async function fetchScanRecord(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<DBScanRow | null> {
  const { data: scan, error: fetchError } = await supabaseAdmin
    .from("scans")
    .select("id, user_id, image_storage_urls, video_storage_urls")
    .eq("id", scanId)
    .single();

  if (fetchError || !scan) {
    return null;
  }

  return scan as DBScanRow;
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
