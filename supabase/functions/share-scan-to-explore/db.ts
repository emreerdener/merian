import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ShareEligibleScanRow {
  id: string;
  user_id: string;
  geoprivacy: string;
  image_storage_urls: string[];
  is_tombstoned: boolean;
  species_id: string | null;
  confirmed_species_id: string | null;
}

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchShareEligibleScan(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ShareEligibleScanRow> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id,user_id,geoprivacy,image_storage_urls,is_tombstoned,species_id,confirmed_species_id")
    .eq("id", scanId)
    .eq("user_id", userId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Scan not found.");
  }

  const row = data as ShareEligibleScanRow;

  if (row.is_tombstoned) {
    throw makeHttpError(409, "Tombstoned scans cannot be shared to Explore.");
  }

  if (row.geoprivacy === "private") {
    throw makeHttpError(409, "Private scans cannot be shared to Explore.");
  }

  if ((row.image_storage_urls?.length ?? 0) === 0) {
    throw makeHttpError(409, "This scan no longer has shareable image media.");
  }

  if (row.confirmed_species_id == null && row.species_id == null) {
    throw makeHttpError(409, "Only biological scans can be shared to Explore.");
  }

  return row;
}

export async function upsertExplorePost(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; shared_at: string }> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .upsert(
      {
        scan_id: scanId,
        user_id: userId,
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
    throw new Error(`Failed to share scan to Explore: ${error?.message ?? "Unknown error"}`);
  }

  return data as { id: string; shared_at: string };
}
