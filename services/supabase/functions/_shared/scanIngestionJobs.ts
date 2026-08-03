import { SupabaseClient } from "@supabase/supabase-js";

export type ScanIngestionJobStatus =
  | "processing"
  | "finalizing"
  | "retrying"
  | "failed_retryable"
  | "failed_terminal"
  | "complete";

export type MutableScanIngestionJobStatus = Exclude<
  ScanIngestionJobStatus,
  "complete"
>;

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
  terminal_reason_code?: string | null;
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
  status: MutableScanIngestionJobStatus;
  stage: string;
  lastError?: string | null;
  retryAfter?: string | null;
  leaseSeconds?: number;
  terminalReasonCode?: string | null;
}

export interface CompleteScanIngestionFinalizationInput {
  scanId: string;
  userId: string;
  promotedUrlsByStorageKey: Map<string, string>;
  deletedStorageKeys: string[];
  responseEnvelope?: Record<string, unknown>;
}

export interface CompleteScanIngestionFinalizationResult {
  result: "completed" | "already_complete";
  responseEnvelope: Record<string, unknown> | null;
}

export interface BeginScanIngestionInput {
  scanId: string;
  userId: string;
  endpoint: string;
  requestPayload: Record<string, unknown>;
  mediaCounts: ScanIngestionMediaCounts;
  mediaObjectKeys: ScanIngestionMediaObjectKeys;
  storageKeys: string[];
  manifestChecksum: string | null;
  payloadChecksum: string | null;
  resumable: boolean;
  inlineMediaRedacted: boolean;
  redactedMediaCounts: Record<string, number>;
  payloadSchemaVersion?: number;
  leaseSeconds?: number;
}

export interface BeginScanIngestionResult {
  uploadSessionIds: string[];
  manifestChecksum: string;
  payloadChecksum: string;
  stage: string;
  alreadyComplete: boolean;
}

export type StrandedScanIngestionRecoveryOutcome =
  | "not_applicable"
  | "job_not_found"
  | "deleted"
  | "already_complete"
  | "complete_without_scan"
  | "terminal"
  | "active"
  | "scan_durable"
  | "quota_retry_ready"
  | "media_restage_required";

export interface StrandedScanIngestionRecovery {
  outcome: StrandedScanIngestionRecoveryOutcome;
  authorizedSourceUserId: string | null;
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

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const INGESTION_STAGE_PATTERN = /^[a-z][a-z0-9_]{1,63}$/;

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

export async function beginScanIngestion(
  input: BeginScanIngestionInput,
  supabaseAdmin: SupabaseClient,
): Promise<BeginScanIngestionResult> {
  const { data, error } = await supabaseAdmin.rpc("begin_scan_ingestion", {
    p_scan_id: input.scanId,
    p_user_id: input.userId,
    p_endpoint: input.endpoint,
    p_request_payload: input.requestPayload,
    p_media_counts: input.mediaCounts,
    p_media_object_keys: input.mediaObjectKeys,
    p_storage_keys: input.storageKeys,
    p_manifest_checksum: input.manifestChecksum,
    p_payload_checksum: input.payloadChecksum,
    p_resumable: input.resumable,
    p_inline_media_redacted: input.inlineMediaRedacted,
    p_redacted_media_counts: input.redactedMediaCounts,
    p_payload_schema_version: input.payloadSchemaVersion ?? 1,
    p_lease_seconds: input.leaseSeconds ?? 300,
  });

  if (error) {
    throw new Error(`beginScanIngestion: ${error.message}`);
  }

  const result = data as {
    upload_session_ids?: unknown;
    manifest_checksum?: unknown;
    payload_checksum?: unknown;
    stage?: unknown;
    already_complete?: unknown;
  } | null;
  if (
    !result ||
    !Array.isArray(result.upload_session_ids) ||
    !result.upload_session_ids.every((value) =>
      typeof value === "string" && UUID_PATTERN.test(value)
    ) ||
    typeof result.manifest_checksum !== "string" ||
    !SHA256_PATTERN.test(result.manifest_checksum) ||
    typeof result.payload_checksum !== "string" ||
    !SHA256_PATTERN.test(result.payload_checksum) ||
    typeof result.stage !== "string" ||
    !INGESTION_STAGE_PATTERN.test(result.stage) ||
    typeof result.already_complete !== "boolean"
  ) {
    throw new Error("beginScanIngestion: malformed RPC response");
  }

  return {
    uploadSessionIds: result.upload_session_ids as string[],
    manifestChecksum: result.manifest_checksum,
    payloadChecksum: result.payload_checksum,
    stage: result.stage,
    alreadyComplete: result.already_complete,
  };
}

function isMissingRecoveryRoutine(error: {
  code?: string | null;
  message?: string | null;
}): boolean {
  if (error.code === "PGRST202") return true;
  return error.code === "42883" &&
    (error.message ?? "").includes(
      "recover_stranded_scan_ingestion_attempt",
    );
}

export async function recoverStrandedScanIngestionAttempt(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<StrandedScanIngestionRecovery | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "recover_stranded_scan_ingestion_attempt",
    {
      p_scan_id: scanId,
      p_user_id: userId,
    },
  );

  // Migration-first deploys can briefly leave an old schema cache in front of
  // new Edge code. Recovery is additive; never weaken owner validation during
  // that window.
  if (error && isMissingRecoveryRoutine(error)) return null;
  if (error) {
    throw new Error(
      `recoverStrandedScanIngestionAttempt: ${error.message ?? error.code}`,
    );
  }

  const value = data as {
    outcome?: unknown;
    authorized_source_user_id?: unknown;
  } | null;
  const outcomes = new Set<StrandedScanIngestionRecoveryOutcome>([
    "not_applicable",
    "job_not_found",
    "deleted",
    "already_complete",
    "complete_without_scan",
    "terminal",
    "active",
    "scan_durable",
    "quota_retry_ready",
    "media_restage_required",
  ]);
  if (
    !value ||
    typeof value.outcome !== "string" ||
    !outcomes.has(value.outcome as StrandedScanIngestionRecoveryOutcome) ||
    !(
      value.authorized_source_user_id == null ||
      (
        typeof value.authorized_source_user_id === "string" &&
        UUID_PATTERN.test(value.authorized_source_user_id)
      )
    )
  ) {
    throw new Error(
      "recoverStrandedScanIngestionAttempt: malformed RPC response",
    );
  }

  return {
    outcome: value.outcome as StrandedScanIngestionRecoveryOutcome,
    authorizedSourceUserId: value.authorized_source_user_id as string | null,
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
  if (input.status === "failed_terminal") {
    const { error } = await supabaseAdmin.rpc(
      "fail_scan_ingestion_terminal",
      {
        p_scan_id: input.scanId,
        p_user_id: input.userId,
        p_stage: input.stage,
        p_last_error: (input.lastError ?? "").slice(0, 2_000),
        p_terminal_reason_code: input.terminalReasonCode ??
          "terminal_scan_failure",
      },
    );
    if (error) {
      throw new Error(`updateScanIngestionJob: ${error.message}`);
    }
    return;
  }

  const update: Record<string, unknown> = {
    status: input.status,
    stage: input.stage,
    last_error: input.lastError ?? null,
    retry_after: input.retryAfter ?? null,
    completed_at: null,
    updated_at: new Date().toISOString(),
  };
  if (input.terminalReasonCode !== undefined) {
    update.terminal_reason_code = input.terminalReasonCode;
  } else {
    update.terminal_reason_code = null;
  }

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

  // Complete and terminal generations are monotonic. In particular, a
  // delayed provider callback must not reopen the user_deleted terminal state
  // installed by the durable scan-deletion fence.
  query = query.not("status", "in", "(complete,failed_terminal)");

  const { error } = await query;
  if (error) {
    throw new Error(`updateScanIngestionJob: ${error.message}`);
  }
}

export async function completeScanIngestionFinalization(
  input: CompleteScanIngestionFinalizationInput,
  supabaseAdmin: SupabaseClient,
): Promise<CompleteScanIngestionFinalizationResult> {
  const promotedUrls = Object.fromEntries(
    [...input.promotedUrlsByStorageKey.entries()].sort(([lhs], [rhs]) =>
      lhs.localeCompare(rhs)
    ),
  );
  const deletedStorageKeys = [
    ...new Set(
      input.deletedStorageKeys.map((value) => value.trim()).filter(Boolean),
    ),
  ].sort();
  const rpcArguments: Record<string, unknown> = {
    p_scan_id: input.scanId,
    p_user_id: input.userId,
    p_response_envelope: input.responseEnvelope ?? null,
    p_promoted_urls_by_storage_key: promotedUrls,
    p_deleted_storage_keys: deletedStorageKeys,
  };
  let { data, error } = await supabaseAdmin.rpc(
    "complete_scan_ingestion_with_entitlement",
    rpcArguments,
  );
  if (
    error &&
    (
      error.code === "PGRST202" ||
      (
        error.code === "42883" &&
        error.message.includes(
          "complete_scan_ingestion_with_entitlement",
        )
      )
    )
  ) {
    // Schema-first rolling deploy compatibility. The cutover migration adds a
    // database fence, so this lower-level path cannot bypass a live hold.
    const fallbackArguments: Record<string, unknown> = {
      p_scan_id: input.scanId,
      p_user_id: input.userId,
      p_promoted_urls_by_storage_key: promotedUrls,
      p_deleted_storage_keys: deletedStorageKeys,
    };
    const fallbackName = input.responseEnvelope
      ? "complete_scan_ingestion_finalization_with_response"
      : "complete_scan_ingestion_finalization";
    if (input.responseEnvelope) {
      fallbackArguments.p_response_envelope = input.responseEnvelope;
    }
    const fallback = await supabaseAdmin.rpc(
      fallbackName,
      fallbackArguments,
    );
    data = fallback.error ? fallback.data : {
      result: fallback.data,
      response_envelope: input.responseEnvelope ?? null,
    };
    error = fallback.error;
  }
  if (error) {
    throw new Error(`completeScanIngestionFinalization: ${error.message}`);
  }
  const value = data as {
    result?: unknown;
    response_envelope?: unknown;
  } | null;
  if (
    !value ||
    (value.result !== "completed" && value.result !== "already_complete") ||
    !(
      value.response_envelope === null ||
      (
        typeof value.response_envelope === "object" &&
        !Array.isArray(value.response_envelope)
      )
    )
  ) {
    throw new Error(
      `completeScanIngestionFinalization: finalization returned ${
        String(data)
      }`,
    );
  }
  return {
    result: value.result,
    responseEnvelope: value.response_envelope as Record<string, unknown> | null,
  };
}

export async function fetchScanIngestionJob(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanIngestionJobRow | null> {
  const { data, error } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    .select(
      "id,scan_id,user_id,endpoint,status,stage,attempt_count,media_counts,media_object_keys,upload_session_ids,manifest_checksum,locked_at,lock_expires_at,retry_after,last_error,terminal_reason_code,completed_at,created_at,updated_at",
    )
    .eq("scan_id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`fetchScanIngestionJob: ${error.message}`);
  }

  return (data ?? null) as unknown as ScanIngestionJobRow | null;
}
