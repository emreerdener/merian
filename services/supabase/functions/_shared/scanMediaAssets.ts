import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type ScanMediaAssetKind = "image" | "video";
export type ScanMediaAssetRole =
  | "display"
  | "playback"
  | "thumbnail"
  | "inference_frame"
  | "audio";
export type ScanMediaAssetStatus =
  | "staged"
  | "promoted"
  | "processing"
  | "ready"
  | "failed"
  | "deleted";

export interface ScanMediaAssetRow {
  kind: ScanMediaAssetKind;
  role?: ScanMediaAssetRole | null;
  status?: ScanMediaAssetStatus | null;
  source?: string | null;
  url?: string | null;
  storage_key?: string | null;
  thumbnail_url?: string | null;
  order_index: number;
  duration_seconds?: number | null;
  has_audio?: boolean | null;
  content_type?: string | null;
  byte_size?: number | null;
  checksum_sha256?: string | null;
  width?: number | null;
  height?: number | null;
  failure_reason?: string | null;
  ready_at?: string | null;
  deleted_at?: string | null;
  metadata?: Record<string, unknown> | null;
}

type NormalizedScanMediaAssetRow = ScanMediaAssetRow & {
  role: ScanMediaAssetRole;
  status: ScanMediaAssetStatus;
  url: string;
  order_index: number;
};

export type ReadyScanMediaAssetRow =
  & Omit<
    NormalizedScanMediaAssetRow,
    "role" | "status"
  >
  & {
    role: "display" | "playback";
    status: "ready";
  };

export function cleanScanMediaAssetRows(
  rows: ScanMediaAssetRow[] | null | undefined,
): ReadyScanMediaAssetRow[] {
  return (rows ?? [])
    .map((row): NormalizedScanMediaAssetRow => ({
      ...row,
      role: normalizeAssetRole(row),
      status: normalizeAssetStatus(row),
      url: typeof row.url === "string" ? row.url.trim() : "",
      thumbnail_url: typeof row.thumbnail_url === "string"
        ? row.thumbnail_url.trim()
        : row.thumbnail_url ?? null,
      order_index: Number.isInteger(row.order_index) && row.order_index >= 0
        ? row.order_index
        : Number.MAX_SAFE_INTEGER,
    }))
    .filter(isReadyVisibleAssetRow)
    .sort((lhs, rhs) => lhs.order_index - rhs.order_index);
}

function isReadyVisibleAssetRow(
  row: NormalizedScanMediaAssetRow,
): row is ReadyScanMediaAssetRow {
  const isVisibleRole = row.role === "display" || row.role === "playback";
  return (row.kind === "image" || row.kind === "video") &&
    row.status === "ready" &&
    isVisibleRole &&
    row.url.length > 0;
}

function normalizeAssetRole(row: ScanMediaAssetRow): ScanMediaAssetRole {
  const role = typeof row.role === "string" ? row.role.trim() : "";
  switch (role) {
    case "display":
    case "playback":
    case "thumbnail":
    case "inference_frame":
    case "audio":
      return role;
    default:
      return row.kind === "video" ? "playback" : "display";
  }
}

function normalizeAssetStatus(row: ScanMediaAssetRow): ScanMediaAssetStatus {
  const status = typeof row.status === "string" ? row.status.trim() : "";
  switch (status) {
    case "staged":
    case "promoted":
    case "processing":
    case "ready":
    case "failed":
    case "deleted":
      return status;
    default:
      return "ready";
  }
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
): Promise<ReadyScanMediaAssetRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select(
      "kind,role,status,source,url,storage_key,thumbnail_url,order_index,duration_seconds,has_audio,content_type,byte_size,checksum_sha256,width,height,failure_reason,ready_at,deleted_at,metadata",
    )
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
): Promise<ReadyScanMediaAssetRow[]> {
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
