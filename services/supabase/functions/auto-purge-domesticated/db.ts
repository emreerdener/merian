import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface DBDomesticatedScanRow {
  id: string;
  image_storage_urls: string[];
  users?: unknown;
}

/**
 * Fetches domesticated scans on free-tier accounts older than 90 days.
 * Limit 500.
 */
export async function fetchStaleDomesticatedScans(
  timestampBoundary: string,
  supabaseAdmin: SupabaseClient,
): Promise<DBDomesticatedScanRow[]> {
  const { data: scans, error: fetchError } = await supabaseAdmin
    .from("scans")
    .select("id, image_storage_urls, users!inner(subscription_tier)")
    .eq("ecology_type", "domesticated")
    .eq("users.subscription_tier", "free")
    .lt("timestamp", timestampBoundary)
    .not("image_storage_urls", "eq", "{}")
    .limit(500);

  if (fetchError) {
    throw new Error(
      `Failed to fetch domesticated scans: ${fetchError.message}`,
    );
  }

  return scans ? (scans as DBDomesticatedScanRow[]) : [];
}

/**
 * Overrides the `image_storage_urls` natively in Postgres back to empty.
 * This does NOT delete the scan row (preserves offline taxonomy).
 */
export async function zeroOutDomesticatedUrls(
  idsToUpdate: string[],
  supabaseAdmin: SupabaseClient,
) {
  if (idsToUpdate.length === 0) return;

  const { error: updateError } = await supabaseAdmin
    .from("scans")
    .update({ image_storage_urls: [] })
    .in("id", idsToUpdate);

  if (updateError) {
    throw new Error(
      `Failed to wipe url arrays on domesticated scans: ${updateError.message}`,
    );
  }
}
