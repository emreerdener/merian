import { SupabaseClient } from "@supabase/supabase-js";
import {
  ClaimedExportJob,
  DBScanRow,
  ExportChunkManifestEntry,
  ExportScope,
  ExportWorkerError,
  ExportWorkPhase,
} from "./types.ts";

export const EXPORT_PAGE_SIZE = 100;

type ExportProjection = "multimedia" | "occurrence";
type PageFetcher<T extends { id: string }> = (
  afterId: string | null,
  limit: number,
) => Promise<T[]>;

interface ClaimRpcRow {
  job_id: unknown;
  user_id: unknown;
  export_scope: unknown;
  include_precise_coordinates: unknown;
  pseudonym_key_version: unknown;
  max_export_rows: unknown;
  max_archive_bytes: unknown;
  archive_object_key: unknown;
  file_url: unknown;
  archive_ready_at: unknown;
  attempt_count: unknown;
  lease_expires_at: unknown;
  work_phase: unknown;
  occurrence_after_id: unknown;
  multimedia_after_id: unknown;
  occurrence_rows: unknown;
  multimedia_rows: unknown;
  csv_bytes: unknown;
  chunk_sequence: unknown;
}

function databaseFailure(message: string, cause: unknown): ExportWorkerError {
  return new ExportWorkerError(
    "database_unavailable",
    message,
    true,
    { cause },
  );
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function parseClaimedJob(value: unknown): ClaimedExportJob {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw databaseFailure("The claim RPC returned an invalid row.", value);
  }
  const row = value as ClaimRpcRow;
  const exportScope = row.export_scope;
  if (
    typeof row.job_id !== "string" ||
    typeof row.user_id !== "string" ||
    (exportScope !== "personal" && exportScope !== "global") ||
    typeof row.include_precise_coordinates !== "boolean" ||
    typeof row.pseudonym_key_version !== "number" ||
    !Number.isSafeInteger(row.pseudonym_key_version) ||
    typeof row.max_export_rows !== "number" ||
    !Number.isSafeInteger(row.max_export_rows) ||
    row.max_export_rows < 1 ||
    typeof row.max_archive_bytes !== "number" ||
    !Number.isSafeInteger(row.max_archive_bytes) ||
    row.max_archive_bytes < 1 ||
    typeof row.attempt_count !== "number" ||
    !Number.isSafeInteger(row.attempt_count) ||
    typeof row.lease_expires_at !== "string" ||
    ![
      "occurrence",
      "multimedia",
      "assembling",
      "delivering",
      "completed",
    ].includes(String(row.work_phase)) ||
    typeof row.occurrence_rows !== "number" ||
    !Number.isSafeInteger(row.occurrence_rows) ||
    typeof row.multimedia_rows !== "number" ||
    !Number.isSafeInteger(row.multimedia_rows) ||
    typeof row.csv_bytes !== "number" ||
    !Number.isSafeInteger(row.csv_bytes) ||
    typeof row.chunk_sequence !== "number" ||
    !Number.isSafeInteger(row.chunk_sequence)
  ) {
    throw databaseFailure("The claim RPC returned malformed state.", row);
  }

  return {
    id: row.job_id,
    userId: row.user_id,
    exportScope,
    includePreciseCoordinates: row.include_precise_coordinates,
    pseudonymKeyVersion: row.pseudonym_key_version,
    maxExportRows: row.max_export_rows,
    maxArchiveBytes: row.max_archive_bytes,
    archiveObjectKey: nullableString(row.archive_object_key),
    fileUrl: nullableString(row.file_url),
    archiveReadyAt: nullableString(row.archive_ready_at),
    attemptCount: row.attempt_count,
    leaseExpiresAt: row.lease_expires_at,
    workPhase: row.work_phase as ExportWorkPhase,
    occurrenceAfterId: nullableString(row.occurrence_after_id),
    multimediaAfterId: nullableString(row.multimedia_after_id),
    occurrenceRows: row.occurrence_rows,
    multimediaRows: row.multimedia_rows,
    csvBytes: row.csv_bytes,
    chunkSequence: row.chunk_sequence,
  };
}

export async function claimExportJob(
  jobId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<ClaimedExportJob | null> {
  const { data, error } = await supabaseAdmin.rpc("claim_export_job_step", {
    p_job_id: jobId,
    p_claim_token: claimToken,
  });
  if (error) {
    throw databaseFailure("Failed to claim the export job.", error);
  }

  if (!Array.isArray(data) || data.length === 0) return null;
  if (data.length !== 1) {
    throw databaseFailure("The claim RPC returned multiple rows.", data);
  }
  return parseClaimedJob(data[0]);
}

export async function fetchDueExportJobIds(
  supabaseAdmin: SupabaseClient,
  limit = 1,
): Promise<string[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_due_export_job_ids",
    { p_limit: limit },
  );
  if (error) {
    throw databaseFailure("Failed to discover due export jobs.", error);
  }
  if (!Array.isArray(data)) {
    throw databaseFailure("The due export RPC returned invalid state.", data);
  }
  return data.map((value) => {
    const jobId = (value as { job_id?: unknown }).job_id;
    if (typeof jobId !== "string" || jobId.length === 0) {
      throw databaseFailure(
        "The due export RPC returned an invalid id.",
        value,
      );
    }
    return jobId;
  });
}

export async function renewExportJobClaim(
  jobId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc("renew_export_job_claim", {
    p_job_id: jobId,
    p_claim_token: claimToken,
  });
  if (error) {
    throw databaseFailure("Failed to renew the export job lease.", error);
  }
  if (data !== true) {
    throw new ExportWorkerError(
      "database_unavailable",
      "The export job lease is no longer owned by this worker.",
      false,
    );
  }
}

export async function stageExportJobArchive(
  jobId: string,
  claimToken: string,
  archiveObjectKey: string,
  fileUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc("stage_export_job_archive", {
    p_job_id: jobId,
    p_claim_token: claimToken,
    p_archive_object_key: archiveObjectKey,
    p_file_url: fileUrl,
  });
  if (error) {
    throw databaseFailure("Failed to stage the export archive.", error);
  }
  if (data !== true) {
    throw new ExportWorkerError(
      "archive_stage_failed",
      "The export archive could not be staged under the active lease.",
      false,
    );
  }
}

export async function completeExportJob(
  jobId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc("complete_export_job", {
    p_job_id: jobId,
    p_claim_token: claimToken,
  });
  if (error) {
    throw databaseFailure("Failed to complete the export job.", error);
  }
  if (data !== true) {
    throw new ExportWorkerError(
      "database_unavailable",
      "The export job completion fence was rejected.",
      false,
    );
  }
}

export async function failExportJob(
  jobId: string,
  claimToken: string,
  failureCode: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("fail_export_job", {
    p_job_id: jobId,
    p_claim_token: claimToken,
    p_failure_code: failureCode,
  });
  if (error) {
    throw databaseFailure("Failed to record the export job failure.", error);
  }
  return data === true;
}

export async function advanceExportJobStep(
  job: ClaimedExportJob,
  claimToken: string,
  phase: "occurrence" | "multimedia",
  nextAfterId: string | null,
  rowCount: number,
  chunkObjectKey: string,
  chunkByteCount: number,
  pageComplete: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<ExportWorkPhase> {
  const { data, error } = await supabaseAdmin.rpc(
    "advance_export_job_step",
    {
      p_job_id: job.id,
      p_claim_token: claimToken,
      p_expected_phase: phase,
      p_next_after_id: nextAfterId,
      p_row_count: rowCount,
      p_chunk_object_key: chunkObjectKey,
      p_chunk_byte_count: chunkByteCount,
      p_page_complete: pageComplete,
    },
  );
  if (error) {
    if (error.code === "54000") {
      throw new ExportWorkerError(
        "export_too_large",
        "The export exceeded its canonical row or byte budget.",
      );
    }
    throw databaseFailure("Failed to advance the export batch.", error);
  }
  if (
    ![
      "occurrence",
      "multimedia",
      "assembling",
      "delivering",
      "completed",
    ].includes(String(data))
  ) {
    throw databaseFailure("The export batch returned an invalid phase.", data);
  }
  return data as ExportWorkPhase;
}

interface ChunkRpcRow {
  chunk_phase?: unknown;
  chunk_sequence?: unknown;
  object_key?: unknown;
  byte_count?: unknown;
}

export async function fetchExportJobChunks(
  jobId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExportChunkManifestEntry[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_export_job_chunks",
    { p_job_id: jobId, p_claim_token: claimToken },
  );
  if (error) {
    throw databaseFailure("Failed to load the export chunk manifest.", error);
  }
  if (!Array.isArray(data)) {
    throw databaseFailure("The export chunk manifest is invalid.", data);
  }

  return data.map((value) => {
    const row = value as ChunkRpcRow;
    if (
      (row.chunk_phase !== "occurrence" &&
        row.chunk_phase !== "multimedia") ||
      typeof row.chunk_sequence !== "number" ||
      !Number.isSafeInteger(row.chunk_sequence) ||
      row.chunk_sequence < 0 ||
      typeof row.object_key !== "string" ||
      row.object_key.length === 0 ||
      typeof row.byte_count !== "number" ||
      !Number.isSafeInteger(row.byte_count) ||
      row.byte_count < 0
    ) {
      throw databaseFailure("The export chunk manifest is malformed.", row);
    }
    return {
      phase: row.chunk_phase,
      sequence: row.chunk_sequence,
      objectKey: row.object_key,
      byteCount: row.byte_count,
    };
  });
}

export async function stagePreparedExportArchive(
  jobId: string,
  claimToken: string,
  archiveObjectKey: string,
  fileUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "stage_prepared_export_archive",
    {
      p_job_id: jobId,
      p_claim_token: claimToken,
      p_archive_object_key: archiveObjectKey,
      p_file_url: fileUrl,
    },
  );
  if (error) {
    throw databaseFailure("Failed to stage the prepared export.", error);
  }
  if (data !== true) {
    throw new ExportWorkerError(
      "archive_stage_failed",
      "The prepared archive lost its active claim.",
      false,
    );
  }
}

export async function completePreparedExportJob(
  jobId: string,
  claimToken: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "complete_prepared_export_job",
    { p_job_id: jobId, p_claim_token: claimToken },
  );
  if (error) {
    throw databaseFailure("Failed to complete the prepared export.", error);
  }
  if (data !== true) {
    throw new ExportWorkerError(
      "database_unavailable",
      "The prepared export completion fence was rejected.",
      false,
    );
  }
}

export async function releaseExportJobStep(
  jobId: string,
  claimToken: string,
  failureCode: string,
  terminal: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "release_export_job_step",
    {
      p_job_id: jobId,
      p_claim_token: claimToken,
      p_failure_code: failureCode,
      p_terminal: terminal,
    },
  );
  if (error) {
    throw databaseFailure("Failed to release the export batch.", error);
  }
  return data === true;
}

export async function fetchUserEmail(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string> {
  const { data: { user }, error } = await supabaseAdmin.auth.admin
    .getUserById(userId);
  if (error || !user?.email) {
    throw databaseFailure(
      "Could not resolve the export delivery email.",
      error,
    );
  }
  return user.email;
}

/**
 * Reusable strict keyset iterator. Each page begins after the last id from the
 * prior page; malformed or non-monotonic provider results fail closed.
 */
export async function* keysetPages<T extends { id: string }>(
  fetchPage: PageFetcher<T>,
  pageSize = EXPORT_PAGE_SIZE,
): AsyncGenerator<T[]> {
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 1000) {
    throw new TypeError("pageSize must be an integer between 1 and 1000.");
  }

  let afterId: string | null = null;
  while (true) {
    const page = await fetchPage(afterId, pageSize);
    if (!Array.isArray(page) || page.length > pageSize) {
      throw databaseFailure("The export query returned an invalid page.", page);
    }
    if (page.length === 0) return;

    let previousId = afterId;
    for (const row of page) {
      if (
        typeof row.id !== "string" ||
        row.id.length === 0 ||
        (previousId !== null && row.id <= previousId)
      ) {
        throw databaseFailure(
          "The export query returned a non-monotonic keyset page.",
          page,
        );
      }
      previousId = row.id;
    }

    yield page;
    afterId = page[page.length - 1].id;
    if (page.length < pageSize) return;
  }
}

function scanSelection(projection: ExportProjection): string {
  if (projection === "multimedia") {
    return `
      id,
      user_id,
      image_storage_urls
    `;
  }
  return `
    id,
    user_id,
    timestamp,
    gps_lat_exact,
    gps_long_exact,
    gps_lat_public,
    gps_long_public,
    coordinate_uncertainty_in_meters,
    life_stage,
    reproductive_condition,
    sex,
    individual_count,
    ecological_interactions,
    ai_confidence_score,
    species_dictionary!species_id (
      scientific_name,
      kingdom,
      phylum,
      class,
      "order",
      family,
      genus,
      iucn_red_list_status
    )
  `;
}

async function fetchExportScanPage(
  userId: string,
  exportScope: ExportScope,
  projection: ExportProjection,
  afterId: string | null,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<DBScanRow[]> {
  let query = supabaseAdmin
    .from("scans")
    .select(scanSelection(projection))
    .eq("is_live_capture", true)
    .eq("is_tombstoned", false)
    .neq("ecology_type", "domesticated")
    .order("id", { ascending: true })
    .limit(limit);

  if (exportScope === "global") {
    query = query.eq("geoprivacy", "open");
  } else {
    query = query.eq("user_id", userId);
  }
  if (afterId !== null) {
    query = query.gt("id", afterId);
  }

  const { data, error } = await query;
  if (error) {
    throw databaseFailure("Failed to fetch an export scan page.", error);
  }
  return (data ?? []) as unknown as DBScanRow[];
}

export function fetchExportScanBatch(
  job: ClaimedExportJob,
  projection: ExportProjection,
  afterId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<DBScanRow[]> {
  return fetchExportScanPage(
    job.userId,
    job.exportScope,
    projection,
    afterId,
    EXPORT_PAGE_SIZE,
    supabaseAdmin,
  );
}

export function fetchExportScanPages(
  job: ClaimedExportJob,
  projection: ExportProjection,
  supabaseAdmin: SupabaseClient,
): AsyncGenerator<DBScanRow[]> {
  return keysetPages((afterId, limit) =>
    fetchExportScanPage(
      job.userId,
      job.exportScope,
      projection,
      afterId,
      limit,
      supabaseAdmin,
    )
  );
}
