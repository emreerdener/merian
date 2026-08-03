import { SupabaseClient } from "@supabase/supabase-js";
import {
  fetchScanIngestionJob,
  ScanIngestionJobRow,
} from "../_shared/scanIngestionJobs.ts";
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

export async function fetchScanStatusJob(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionJobRow | null> {
  return await fetchScanIngestionJob(scanId, userId, supabaseAdmin);
}

export type ComplimentaryScanState = "held" | "consumed" | "released";

interface ComplimentaryScanStateRow {
  client_scan_id: string;
  complimentary_state: ComplimentaryScanState;
}

export async function fetchComplimentaryScanStates(
  scanIds: string[],
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<Map<string, ComplimentaryScanState>> {
  const validScanIds = [
    ...new Set(
      scanIds.filter((scanId) =>
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
          .test(scanId)
      ),
    ),
  ];
  if (validScanIds.length === 0) return new Map();

  const { data, error } = await supabaseAdmin.rpc(
    "get_complimentary_scan_states_service",
    {
      p_user_id: userId,
      p_scan_ids: validScanIds,
    },
  );
  if (error) {
    throw new Error(`fetchComplimentaryScanStates: ${error.message}`);
  }

  const result = new Map<string, ComplimentaryScanState>();
  for (const rawRow of Array.isArray(data) ? data : []) {
    const row = rawRow as Partial<ComplimentaryScanStateRow>;
    if (
      typeof row.client_scan_id !== "string" ||
      (row.complimentary_state !== "held" &&
        row.complimentary_state !== "consumed" &&
        row.complimentary_state !== "released")
    ) {
      throw new Error("fetchComplimentaryScanStates: invalid database row");
    }
    result.set(row.client_scan_id.toLowerCase(), row.complimentary_state);
  }
  return result;
}
