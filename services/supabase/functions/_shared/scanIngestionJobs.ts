import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type ScanIngestionJobStatus =
  | "processing"
  | "finalizing"
  | "retrying"
  | "failed_retryable"
  | "failed_terminal"
  | "complete";

export type ClientScanIngestionJobStatus =
  | "processing"
  | "finalizing"
  | "retrying"
  | "failed_retryable"
  | "failed"
  | "complete";

export interface ScanIngestionMediaCounts {
  image_count: number;
  audio_count: number;
  video_count: number;
  required_video_count: number;
  video_frame_count: number;
  video_inference_frame_count?: number;
  has_description?: boolean;
}

export interface ScanIngestionMediaObjectKeys {
  image: string[];
  audio: string[];
  video: string[];
}

export interface ScanIngestionJobRow {
  id: string;
  scan_id: string;
  user_id: string;
  endpoint: string;
  status: ScanIngestionJobStatus;
  stage: string;
  attempt_count: number;
  media_counts?: Record<string, unknown> | null;
  media_object_keys?: Record<string, unknown> | null;
  upload_session_ids?: string[] | null;
  manifest_checksum?: string | null;
  locked_at?: string | null;
  lock_expires_at?: string | null;
  retry_after?: string | null;
  last_error?: string | null;
  completed_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface ClaimScanIngestionJobInput {
  scanId: string;
  userId: string;
  endpoint: string;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  uploadSessionIds?: string[];
  manifestChecksum?: string | null;
  leaseSeconds?: number;
}

export interface UpdateScanIngestionJobInput {
  scanId: string;
  userId: string;
  status: ScanIngestionJobStatus;
  stage: string;
  lastError?: string | null;
  retryAfter?: string | null;
  leaseSeconds?: number;
}

export interface ClientScanIngestionJobState {
  status: ClientScanIngestionJobStatus;
  stage: string;
  attempt_count: number;
  retry_after?: string | null;
  last_error?: string | null;
}

function cleanStringArray(values: string[] | undefined): string[] {
  return [
    ...new Set(
      (values ?? []).map((value) => value.trim()).filter((
        value,
      ) => value.length > 0),
    ),
  ];
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, entryValue]) => entryValue !== undefined)
      .sort(([lhs], [rhs]) => lhs.localeCompare(rhs));
    return `{${
      entries.map(([key, entryValue]) =>
        `${JSON.stringify(key)}:${stableJson(entryValue)}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value);
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function scanIngestionManifestChecksum(input: {
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  uploadSessionIds?: string[];
}): Promise<string> {
  const normalized = {
    mediaCounts: input.mediaCounts,
    mediaObjectKeys: {
      image: cleanStringArray(input.mediaObjectKeys.image),
      audio: cleanStringArray(input.mediaObjectKeys.audio),
      video: cleanStringArray(input.mediaObjectKeys.video),
    },
    uploadSessionIds: cleanStringArray(input.uploadSessionIds).sort(),
  };
  const bytes = new TextEncoder().encode(stableJson(normalized));
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

export function scanIngestionMediaObjectKeys(input: {
  imageKeys?: string[];
  audioKeys?: string[];
  videoKeys?: string[];
}): ScanIngestionMediaObjectKeys {
  return {
    image: cleanStringArray(input.imageKeys),
    audio: cleanStringArray(input.audioKeys),
    video: cleanStringArray(input.videoKeys),
  };
}

export function scanIngestionClientState(
  row: ScanIngestionJobRow | null | undefined,
): ClientScanIngestionJobState | null {
  if (!row) return null;
  const status: ClientScanIngestionJobStatus = row.status === "failed_terminal"
    ? "failed"
    : row.status;
  return {
    status,
    stage: row.stage,
    attempt_count: row.attempt_count,
    retry_after: row.retry_after ?? null,
    last_error: row.status === "failed_retryable" ||
        row.status === "failed_terminal"
      ? row.last_error ?? null
      : null,
  };
}

export async function claimScanIngestionJob(
  input: ClaimScanIngestionJobInput,
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionJobRow> {
  const { data, error } = await supabaseAdmin.rpc("claim_scan_ingestion_job", {
    p_scan_id: input.scanId,
    p_user_id: input.userId,
    p_endpoint: input.endpoint,
    p_media_counts: input.mediaCounts,
    p_media_object_keys: input.mediaObjectKeys,
    p_upload_session_ids: input.uploadSessionIds ?? [],
    p_manifest_checksum: input.manifestChecksum ?? null,
    p_lease_seconds: input.leaseSeconds ?? 300,
  });

  if (error) {
    throw new Error(`claimScanIngestionJob: ${error.message}`);
  }

  return data as unknown as ScanIngestionJobRow;
}

export async function updateScanIngestionJob(
  input: UpdateScanIngestionJobInput,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const update: Record<string, unknown> = {
    status: input.status,
    stage: input.stage,
    last_error: input.lastError ?? null,
    retry_after: input.retryAfter ?? null,
    completed_at: input.status === "complete" ? new Date().toISOString() : null,
    updated_at: new Date().toISOString(),
  };

  if (input.status === "processing" || input.status === "finalizing") {
    const leaseSeconds = Math.max(input.leaseSeconds ?? 300, 30);
    update.locked_at = new Date().toISOString();
    update.lock_expires_at = new Date(Date.now() + leaseSeconds * 1000)
      .toISOString();
  }

  let query = supabaseAdmin
    .from("scan_ingestion_jobs")
    .update(update)
    .eq("scan_id", input.scanId)
    .eq("user_id", input.userId);

  if (input.status !== "complete") {
    query = query.neq("status", "complete");
  }

  const { error } = await query;
  if (error) {
    throw new Error(`updateScanIngestionJob: ${error.message}`);
  }
}

export async function fetchScanIngestionJob(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionJobRow | null> {
  const { data, error } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    .select(
      "id,scan_id,user_id,endpoint,status,stage,attempt_count,media_counts,media_object_keys,upload_session_ids,manifest_checksum,locked_at,lock_expires_at,retry_after,last_error,completed_at,created_at,updated_at",
    )
    .eq("scan_id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`fetchScanIngestionJob: ${error.message}`);
  }

  return (data ?? null) as unknown as ScanIngestionJobRow | null;
}
