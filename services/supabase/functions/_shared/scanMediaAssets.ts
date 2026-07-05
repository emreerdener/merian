import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type ScanMediaAssetKind = "image" | "video";

export interface ScanMediaAssetRow {
  kind: ScanMediaAssetKind;
  url: string;
  thumbnail_url?: string | null;
  order_index: number;
  duration_seconds?: number | null;
  has_audio?: boolean | null;
}

export function cleanScanMediaAssetRows(
  rows: ScanMediaAssetRow[] | null | undefined,
): ScanMediaAssetRow[] {
  return (rows ?? [])
    .map((row) => ({
      ...row,
      url: typeof row.url === "string" ? row.url.trim() : "",
      thumbnail_url: typeof row.thumbnail_url === "string"
        ? row.thumbnail_url.trim()
        : row.thumbnail_url ?? null,
      order_index: Number.isInteger(row.order_index) && row.order_index >= 0
        ? row.order_index
        : Number.MAX_SAFE_INTEGER,
    }))
    .filter((row) =>
      (row.kind === "image" || row.kind === "video") && row.url.length > 0
    )
    .sort((lhs, rhs) => lhs.order_index - rhs.order_index);
}

export function countVideoScanMediaAssets(
  rows: ScanMediaAssetRow[] | null | undefined,
): number {
  return cleanScanMediaAssetRows(rows).filter((row) => row.kind === "video")
    .length;
}

export async function fetchScanMediaAssets(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanMediaAssetRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select("kind,url,thumbnail_url,order_index,duration_seconds,has_audio")
    .eq("scan_id", scanId)
    .order("order_index", { ascending: true });

  if (error) {
    throw new Error(`fetchScanMediaAssets: ${error.message}`);
  }

  return cleanScanMediaAssetRows(data as ScanMediaAssetRow[] | null);
}

export async function fetchScanMediaAssetsBestEffort(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanMediaAssetRow[]> {
  try {
    return await fetchScanMediaAssets(scanId, supabaseAdmin);
  } catch (error) {
    console.error(JSON.stringify({
      event: "scan_media_assets_fetch_failed",
      scan_id: scanId,
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
    return [];
  }
}

export async function refreshScanMediaAssets(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc("refresh_scan_media_assets", {
    target_scan_id: scanId,
  });

  if (error) {
    throw new Error(`refreshScanMediaAssets: ${error.message}`);
  }
}

export async function refreshScanMediaAssetsBestEffort(
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  try {
    await refreshScanMediaAssets(scanId, supabaseAdmin);
  } catch (error) {
    console.error(JSON.stringify({
      event: "scan_media_assets_refresh_failed",
      scan_id: scanId,
      error: error instanceof Error ? error.message : String(error),
      ts: new Date().toISOString(),
    }));
  }
}
