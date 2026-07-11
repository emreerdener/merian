import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type ScanMediaAssetKind = "image" | "video" | "audio";
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
export type ReadyScanMediaAssetKind = "image" | "video" | "audio";

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

export interface StagedScanMediaAssetInput {
  userId: string;
  clientScanId: string;
  uploadSessionId: string;
  kind: ScanMediaAssetKind;
  role: ScanMediaAssetRole;
  storageKey: string;
  orderIndex: number;
  contentType: string;
  byteSize?: number | null;
  metadata?: Record<string, unknown> | null;
}

export interface StagedScanMediaAssetRow {
  id: string;
  storage_key: string;
  upload_session_id: string;
  order_index: number;
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
    kind: ReadyScanMediaAssetKind;
    role: "display" | "playback" | "audio";
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
  const isPublicMediaKind = row.kind === "image" || row.kind === "video" ||
    row.kind === "audio";
  const isVisibleRole = row.role === "display" || row.role === "playback" ||
    row.role === "audio";
  return isPublicMediaKind &&
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

export async function createStagedScanMediaAssets(
  inputs: StagedScanMediaAssetInput[],
  supabaseAdmin: SupabaseClient,
): Promise<StagedScanMediaAssetRow[]> {
  if (inputs.length === 0) return [];

  const rows = inputs.map((input) => ({
    scan_id: null,
    client_scan_id: input.clientScanId,
    upload_session_id: input.uploadSessionId,
    user_id: input.userId,
    kind: input.kind,
    role: input.role,
    status: "staged",
    source: "capture_upload",
    url: null,
    storage_key: input.storageKey,
    thumbnail_url: null,
    order_index: input.orderIndex,
    duration_seconds: null,
    has_audio: false,
    content_type: input.contentType,
    byte_size: input.byteSize ?? null,
    failure_reason: null,
    ready_at: null,
    deleted_at: null,
    metadata: input.metadata ?? {},
  }));

  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .insert(rows)
    .select("id,storage_key,upload_session_id,order_index")
    .order("order_index", { ascending: true });

  if (error) {
    throw new Error(`createStagedScanMediaAssets: ${error.message}`);
  }

  return (data ?? []) as StagedScanMediaAssetRow[];
}

export async function fetchCaptureUploadSessionIdsForKeys(
  input: {
    userId: string;
    clientScanId: string;
    storageKeys: string[];
  },
  supabaseAdmin: SupabaseClient,
): Promise<string[]> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scan_media_assets")
    .select("upload_session_id")
    .eq("user_id", input.userId)
    .eq("client_scan_id", input.clientScanId)
    .eq("source", "capture_upload")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`fetchCaptureUploadSessionIdsForKeys: ${error.message}`);
  }

  return [
    ...new Set(
      ((data ?? []) as Array<{ upload_session_id?: string | null }>)
        .map((row) => row.upload_session_id?.trim() ?? "")
        .filter((id) => id.length > 0),
    ),
  ].sort();
}

export async function markStagedScanMediaAssetsPromoted(
  input: {
    userId: string;
    scanId: string;
    promotedUrlsByStorageKey: Map<string, string>;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  await updateStagedScanMediaAssets(
    input.userId,
    input.promotedUrlsByStorageKey,
    async (storageKey, publicUrl) => {
      const { error } = await supabaseAdmin
        .from("scan_media_assets")
        .update({
          scan_id: input.scanId,
          status: "promoted",
          url: publicUrl,
          failure_reason: null,
          deleted_at: null,
        })
        .eq("user_id", input.userId)
        .eq("source", "capture_upload")
        .eq("status", "staged")
        .eq("storage_key", storageKey);
      return error?.message ?? null;
    },
  );
}

export async function markStagedScanMediaAssetsFailed(
  input: {
    userId: string;
    storageKeys: string[];
    failureReason: string;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return;

  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      status: "failed",
      failure_reason: input.failureReason.slice(0, 500),
    })
    .eq("user_id", input.userId)
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`markStagedScanMediaAssetsFailed: ${error.message}`);
  }
}

export async function markStagedScanMediaAssetsDeleted(
  input: {
    userId: string;
    scanId?: string | null;
    storageKeys: string[];
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const uniqueKeys = [...new Set(input.storageKeys.map((key) => key.trim()))]
    .filter((key) => key.length > 0);
  if (uniqueKeys.length === 0) return;

  const { error } = await supabaseAdmin
    .from("scan_media_assets")
    .update({
      scan_id: input.scanId ?? null,
      status: "deleted",
      deleted_at: new Date().toISOString(),
      failure_reason: null,
    })
    .eq("user_id", input.userId)
    .eq("source", "capture_upload")
    .eq("status", "staged")
    .in("storage_key", uniqueKeys);

  if (error) {
    throw new Error(`markStagedScanMediaAssetsDeleted: ${error.message}`);
  }
}

async function updateStagedScanMediaAssets(
  userId: string,
  urlsByStorageKey: Map<string, string>,
  update: (storageKey: string, publicUrl: string) => Promise<string | null>,
): Promise<void> {
  const failures: string[] = [];
  for (const [storageKey, publicUrl] of urlsByStorageKey) {
    const cleanStorageKey = storageKey.trim();
    const cleanPublicUrl = publicUrl.trim();
    if (cleanStorageKey.length === 0 || cleanPublicUrl.length === 0) continue;
    const errorMessage = await update(cleanStorageKey, cleanPublicUrl);
    if (errorMessage) {
      failures.push(`${cleanStorageKey}: ${errorMessage}`);
    }
  }

  if (failures.length > 0) {
    throw new Error(
      `updateStagedScanMediaAssets(${userId}) failed: ${failures.join("; ")}`,
    );
  }
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
