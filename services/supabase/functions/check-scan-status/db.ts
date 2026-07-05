import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  fetchScanMediaAssetsBestEffort,
  ScanMediaAssetRow,
} from "../_shared/scanMediaAssets.ts";

export async function fetchScanOwnership(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id")
    .eq("id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`fetchScanOwnership: ${error.message}`);
  }

  return data?.id != null;
}

export interface ScanStatusMediaRow {
  id: string;
  video_storage_urls?: string[] | null;
  captured_media?: unknown[] | null;
  media_assets?: ScanMediaAssetRow[] | null;
}

export async function fetchScanStatusMedia(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanStatusMediaRow | null> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id,video_storage_urls,captured_media")
    .eq("id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`fetchScanStatusMedia: ${error.message}`);
  }

  const row = (data as ScanStatusMediaRow | null) ?? null;
  if (!row) return null;

  return {
    ...row,
    media_assets: await fetchScanMediaAssetsBestEffort(scanId, supabaseAdmin),
  };
}
