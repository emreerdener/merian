import { SupabaseClient } from "@supabase/supabase-js";

export interface ReplayableScanIngestionRow {
  scan_id: string;
  user_id: string;
  endpoint: string;
  status: string;
  stage: string;
  attempt_count: number;
  media_counts: Record<string, unknown> | null;
  media_object_keys: Record<string, unknown> | null;
  upload_session_ids: string[] | null;
  manifest_checksum: string | null;
  request_payload: Record<string, unknown>;
  payload_checksum: string | null;
  replay_attempt_count: number;
}

export interface ReplayScanRow {
  id: string;
  user_id: string;
  video_storage_urls: string[] | null;
  captured_media: unknown[] | null;
}

export async function claimReplayableScanIngestionJobs(
  input: {
    limit: number;
    leaseSeconds: number;
  },
  supabaseAdmin: SupabaseClient,
): Promise<ReplayableScanIngestionRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_replayable_scan_ingestion_jobs",
    {
      p_limit: input.limit,
      p_lease_seconds: input.leaseSeconds,
    },
  );

  if (error) {
    throw new Error(`claimReplayableScanIngestionJobs: ${error.message}`);
  }

  return (data ?? []) as unknown as ReplayableScanIngestionRow[];
}

export async function fetchReplayScans(
  scanIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<ReplayScanRow[]> {
  const uniqueScanIds = [...new Set(scanIds.map((id) => id.trim()))].filter((
    id,
  ) => id.length > 0);
  if (uniqueScanIds.length === 0) return [];

  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id,user_id,video_storage_urls,captured_media")
    .in("id", uniqueScanIds);

  if (error) {
    throw new Error(`fetchReplayScans: ${error.message}`);
  }

  return (data ?? []) as unknown as ReplayScanRow[];
}

export async function markReplayJobComplete(
  input: {
    scanId: string;
    userId: string;
    stage: string;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const now = new Date().toISOString();
  const { error: jobError } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    .update({
      status: "complete",
      stage: input.stage,
      retry_after: null,
      last_error: null,
      completed_at: now,
      updated_at: now,
    })
    .eq("scan_id", input.scanId)
    .eq("user_id", input.userId)
    .neq("status", "complete");

  if (jobError) {
    throw new Error(`markReplayJobComplete: ${jobError.message}`);
  }

  const { error: intentError } = await supabaseAdmin
    .from("scan_ingestion_intents")
    .update({
      last_replay_error: null,
      updated_at: now,
    })
    .eq("scan_id", input.scanId)
    .eq("user_id", input.userId);

  if (intentError) {
    throw new Error(`markReplayJobComplete intent: ${intentError.message}`);
  }
}

export async function markReplayDispatchFailure(
  input: {
    scanId: string;
    userId: string;
    stage: string;
    errorMessage: string;
    retryAfterIso: string | null;
    terminal?: boolean;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const now = new Date().toISOString();
  const status = input.terminal ? "failed_terminal" : "failed_retryable";
  const { error: jobError } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    .update({
      status,
      stage: input.stage,
      last_error: input.errorMessage.slice(0, 500),
      retry_after: input.terminal ? null : input.retryAfterIso,
      updated_at: now,
    })
    .eq("scan_id", input.scanId)
    .eq("user_id", input.userId)
    .eq("status", "retrying")
    .eq("stage", "server_replay_claimed");

  if (jobError) {
    throw new Error(`markReplayDispatchFailure: ${jobError.message}`);
  }

  const { error: intentError } = await supabaseAdmin
    .from("scan_ingestion_intents")
    .update({
      last_replay_error: input.errorMessage.slice(0, 500),
      updated_at: now,
    })
    .eq("scan_id", input.scanId)
    .eq("user_id", input.userId);

  if (intentError) {
    throw new Error(
      `markReplayDispatchFailure intent: ${intentError.message}`,
    );
  }
}
