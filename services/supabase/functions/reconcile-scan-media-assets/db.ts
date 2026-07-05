import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import type {
  ScanMediaAssetKind,
  ScanMediaAssetRole,
} from "../_shared/scanMediaAssets.ts";

export interface ReconciliationAssetRow {
  id: string;
  user_id: string;
  client_scan_id: string | null;
  scan_id: string | null;
  kind: ScanMediaAssetKind;
  role: ScanMediaAssetRole;
  status: string;
  source: string;
  url: string | null;
  storage_key: string | null;
  order_index: number;
  content_type: string | null;
  byte_size: number | null;
  created_at: string;
  updated_at: string;
}

export interface ReconciliationScanRow {
  id: string;
  user_id: string;
  image_storage_urls: string[] | null;
  video_storage_urls: string[] | null;
  captured_media: unknown[] | null;
  inference_tier: string | null;
}

export interface ReconciliationRunInsert {
  started_at: string;
  finished_at: string;
  status: "success" | "partial_failure" | "failed" | "dry_run";
  scanned_count: number;
  promoted_count: number;
  repaired_video_scan_count: number;
  deleted_staging_object_count: number;
  failed_asset_count: number;
  missing_object_count: number;
  still_pending_count: number;
  error_count: number;
  errors: unknown[];
}

export async function fetchStaleCaptureUploadAssets(
  cutoffIso: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ReconciliationAssetRow[]> {
  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select(
      [
        "id",
        "user_id",
        "client_scan_id",
        "scan_id",
        "kind",
        "role",
        "status",
        "source",
        "url",
        "storage_key",
        "order_index",
        "content_type",
        "byte_size",
        "created_at",
        "updated_at",
      ].join(","),
    )
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .lte("created_at", cutoffIso)
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    throw new Error(`fetchStaleCaptureUploadAssets: ${error.message}`);
  }

  return (data ?? []) as unknown as ReconciliationAssetRow[];
}

export async function fetchReconciliationScans(
  scanIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ReconciliationScanRow[]> {
  const uniqueScanIds = [...new Set(scanIds.map((id) => id.trim()))].filter((
    id,
  ) => id.length > 0);
  if (uniqueScanIds.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scans")
    .select(
      "id,user_id,image_storage_urls,video_storage_urls,captured_media,inference_tier",
    )
    .in("id", uniqueScanIds);

  if (error) {
    throw new Error(`fetchReconciliationScans: ${error.message}`);
  }

  return (data ?? []) as unknown as ReconciliationScanRow[];
}

export async function markCaptureUploadAssetPromoted(
  assetId: string,
  scanId: string,
  publicUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      scan_id: scanId,
      status: "promoted",
      url: publicUrl,
      failure_reason: null,
      deleted_at: null,
    })
    .eq("id", assetId)
    .eq("source", "capture_upload")
    .eq("status", "staged");

  if (error) {
    throw new Error(`markCaptureUploadAssetPromoted: ${error.message}`);
  }
}

export async function markCaptureUploadAssetDeleted(
  assetId: string,
  scanId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      scan_id: scanId,
      status: "deleted",
      deleted_at: new Date().toISOString(),
      failure_reason: null,
    })
    .eq("id", assetId)
    .eq("source", "capture_upload")
    .eq("status", "staged");

  if (error) {
    throw new Error(`markCaptureUploadAssetDeleted: ${error.message}`);
  }
}

export async function markCaptureUploadAssetFailed(
  assetId: string,
  failureReason: string,
  objectDeleted: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const update: Record<string, unknown> = {
    status: "failed",
    failure_reason: failureReason.slice(0, 500),
  };
  if (objectDeleted) {
    update.deleted_at = new Date().toISOString();
  }

  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update(update)
    .eq("id", assetId)
    .eq("source", "capture_upload")
    .eq("status", "staged");

  if (error) {
    throw new Error(`markCaptureUploadAssetFailed: ${error.message}`);
  }
}

export async function updateScanVideoMedia(
  scanId: string,
  videoStorageUrls: string[],
  capturedMedia: unknown[] | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scans")
    .update({
      video_storage_urls: videoStorageUrls,
      captured_media: capturedMedia,
    })
    .eq("id", scanId);

  if (error) {
    throw new Error(`updateScanVideoMedia: ${error.message}`);
  }
}

export async function recordScanMediaReconciliationRun(
  row: ReconciliationRunInsert,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("scan_media_reconciliation_runs")
    .insert(row);

  if (error) {
    throw new Error(`recordScanMediaReconciliationRun: ${error.message}`);
  }
}
