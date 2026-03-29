import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface DBScanRow {
  id: string;
  image_storage_urls: string[];
}

/**
 * Fetches non-biological scans older than the specified timestamp boundary.
 * Limited to 500 rows to prevent Deno memory pressure and R2 API throttling.
 */
export async function fetchStaleNonBioScans(
  timestampBoundary: string,
  supabaseAdmin: SupabaseClient,
): Promise<DBScanRow[]> {
  const { data: scans, error: fetchError } = await supabaseAdmin
    .from("scans")
    .select("id, image_storage_urls")
    .eq("is_biological_subject", false)
    .lt("timestamp", timestampBoundary)
    .limit(500);

  if (fetchError) {
    throw new Error(
      `Failed to fetch non-biological scans: ${fetchError.message}`,
    );
  }

  return scans ? (scans as DBScanRow[]) : [];
}

/**
 * Executes a batch deletion of `scans` by ID.
 * Expects the underlying storage buckets to be wiped prior to invocation.
 */
export async function deleteScansBulk(
  idsToDelete: string[],
  supabaseAdmin: SupabaseClient,
) {
  if (idsToDelete.length === 0) return;

  const { error: deleteError } = await supabaseAdmin
    .from("scans")
    .delete()
    .in("id", idsToDelete);

  if (deleteError) {
    throw new Error(
      `Failed to batch delete scans from database: ${deleteError.message}`,
    );
  }
}
