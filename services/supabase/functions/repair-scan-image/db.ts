import type { SupabaseClient } from "@supabase/supabase-js";

export interface ScanImageRepairCounts {
  updatedScanCount: number;
  updatedPostMediaCount: number;
}

export async function ownedScanImageReferenceExists(
  userId: string,
  sourceUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id")
    .eq("user_id", userId)
    .eq("is_tombstoned", false)
    .contains("image_storage_urls", [sourceUrl])
    .limit(1);

  if (error) {
    throw new Error(`Could not inspect owned scan media: ${error.message}`);
  }

  return (data?.length ?? 0) > 0;
}

export async function persistOwnedScanImageRepair(
  userId: string,
  sourceUrl: string,
  replacementUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanImageRepairCounts> {
  const { data, error } = await supabaseAdmin.rpc(
    "repair_owned_scan_image_reference",
    {
      p_user_id: userId,
      p_source_url: sourceUrl,
      p_replacement_url: replacementUrl,
    },
  );

  if (
    error || data == null || typeof data !== "object" || Array.isArray(data)
  ) {
    throw new Error("Could not persist scan image repair.");
  }

  const row = data as Record<string, unknown>;
  if (
    !Number.isInteger(row.updated_scan_count) ||
    (row.updated_scan_count as number) < 0 ||
    !Number.isInteger(row.updated_post_media_count) ||
    (row.updated_post_media_count as number) < 0
  ) {
    throw new Error("Scan image repair returned invalid state.");
  }

  return {
    updatedScanCount: row.updated_scan_count as number,
    updatedPostMediaCount: row.updated_post_media_count as number,
  };
}
