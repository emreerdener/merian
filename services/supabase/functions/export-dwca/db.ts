import { SupabaseClient } from "@supabase/supabase-js";
import {
  EXPORT_PAGE_SIZE,
  MAXIMUM_DWCA_IMAGE_URL_BYTES,
  MAXIMUM_DWCA_IMAGE_URLS,
  MAXIMUM_DWCA_INTERACTION_BYTES,
  MAXIMUM_DWCA_INTERACTIONS,
  MAXIMUM_DWCA_IUCN_STATUS_BYTES,
  MAXIMUM_DWCA_SCIENTIFIC_NAME_BYTES,
  MAXIMUM_DWCA_TAXON_RANK_BYTES,
  MAXIMUM_EXPORT_SOURCE_PAGE_BYTES,
} from "./limits.ts";
import {
  ClaimedExportJob,
  DBScanRow,
  ExportChunkManifestEntry,
  ExportScanBatch,
  ExportWorkerError,
  ExportWorkPhase,
} from "./types.ts";

export { EXPORT_PAGE_SIZE } from "./limits.ts";

type ExportProjection = "multimedia" | "occurrence";

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

interface ExportScanRpcRow {
  scan_id: unknown;
  scan_payload: unknown;
  source_byte_count: unknown;
  page_complete: unknown;
  source_row_oversize: unknown;
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

function containsControlCharacter(value: string): boolean {
  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0;
    if (codePoint <= 0x1f || codePoint === 0x7f) return true;
  }
  return false;
}

function utf8LengthExceeds(value: string, maximumBytes: number): boolean {
  let byteLength = 0;
  for (const character of value) {
    const codePoint = character.codePointAt(0) ?? 0;
    byteLength += codePoint <= 0x7f
      ? 1
      : codePoint <= 0x7ff
      ? 2
      : codePoint <= 0xffff
      ? 3
      : 4;
    if (byteLength > maximumBytes) return true;
  }
  return false;
}

function assertBoundedString(
  value: unknown,
  maximumBytes: number,
  context: string,
  nullable = false,
): void {
  if (
    (nullable && value === null) ||
    (
      typeof value === "string" &&
      !utf8LengthExceeds(value, maximumBytes)
    )
  ) {
    return;
  }
  throw databaseFailure(`${context} exceeded its byte bound.`, value);
}

function parseBoundedStringArray(
  value: unknown,
  maximumElements: number,
  maximumElementBytes: number,
  context: string,
): string[] {
  if (!Array.isArray(value) || value.length > maximumElements) {
    throw databaseFailure(`${context} exceeded its cardinality bound.`, value);
  }
  for (const element of value) {
    if (
      typeof element !== "string" ||
      utf8LengthExceeds(element, maximumElementBytes) ||
      containsControlCharacter(element)
    ) {
      throw databaseFailure(`${context} contained an invalid element.`, value);
    }
  }
  return value;
}

function parseExportScanPayload(
  value: unknown,
  expectedId: string,
  projection: ExportProjection,
): DBScanRow {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw databaseFailure("The export scan payload was not an object.", value);
  }
  const payload = value as Record<string, unknown>;
  if (
    payload.id !== expectedId ||
    (payload.user_id !== null && typeof payload.user_id !== "string")
  ) {
    throw databaseFailure(
      "The export scan payload had invalid identity.",
      value,
    );
  }

  if (projection === "multimedia") {
    payload.image_storage_urls = parseBoundedStringArray(
      payload.image_storage_urls,
      MAXIMUM_DWCA_IMAGE_URLS,
      MAXIMUM_DWCA_IMAGE_URL_BYTES,
      "The export media array",
    );
  } else {
    payload.ecological_interactions = parseBoundedStringArray(
      payload.ecological_interactions,
      MAXIMUM_DWCA_INTERACTIONS,
      MAXIMUM_DWCA_INTERACTION_BYTES,
      "The export interaction array",
    );
    if (payload.species_dictionary === null) {
      return payload as unknown as DBScanRow;
    }
    if (
      !payload.species_dictionary ||
      typeof payload.species_dictionary !== "object" ||
      Array.isArray(payload.species_dictionary)
    ) {
      throw databaseFailure(
        "The export taxonomy payload was invalid.",
        payload.species_dictionary,
      );
    }
    const taxonomy = payload.species_dictionary as Record<string, unknown>;
    assertBoundedString(
      taxonomy.scientific_name,
      MAXIMUM_DWCA_SCIENTIFIC_NAME_BYTES,
      "The export scientific name",
    );
    for (
      const rank of [
        "kingdom",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
      ]
    ) {
      assertBoundedString(
        taxonomy[rank],
        MAXIMUM_DWCA_TAXON_RANK_BYTES,
        `The export ${rank} field`,
      );
    }
    assertBoundedString(
      taxonomy.iucn_red_list_status,
      MAXIMUM_DWCA_IUCN_STATUS_BYTES,
      "The export IUCN status",
      true,
    );
  }

  return payload as unknown as DBScanRow;
}

function parseExportScanBatch(
  value: unknown,
  projection: ExportProjection,
): ExportScanBatch {
  if (!Array.isArray(value) || value.length < 1) {
    throw databaseFailure("The export scan RPC returned invalid state.", value);
  }
  if (
    value.some((row) => !row || typeof row !== "object" || Array.isArray(row))
  ) {
    throw databaseFailure(
      "The export scan RPC returned a non-object row.",
      value,
    );
  }
  const rpcRows = value as ExportScanRpcRow[];
  const sentinel = rpcRows.find((row) => row.scan_payload === null);
  if (sentinel) {
    if (
      rpcRows.length !== 1 ||
      sentinel.scan_id !== null ||
      typeof sentinel.page_complete !== "boolean" ||
      typeof sentinel.source_row_oversize !== "boolean" ||
      typeof sentinel.source_byte_count !== "number" ||
      !Number.isSafeInteger(sentinel.source_byte_count) ||
      sentinel.source_byte_count < 0
    ) {
      throw databaseFailure(
        "The export scan RPC returned an invalid sentinel.",
        value,
      );
    }
    if (
      sentinel.source_row_oversize &&
      !sentinel.page_complete &&
      sentinel.source_byte_count > MAXIMUM_EXPORT_SOURCE_PAGE_BYTES
    ) {
      throw new ExportWorkerError(
        "export_too_large",
        "An export source row exceeded its canonical byte bound.",
      );
    }
    if (
      !sentinel.source_row_oversize &&
      sentinel.page_complete &&
      sentinel.source_byte_count === 0
    ) {
      return { scans: [], sourceByteCount: 0, pageComplete: true };
    }
    throw databaseFailure(
      "The export scan RPC returned an inconsistent sentinel.",
      value,
    );
  }

  if (rpcRows.length > EXPORT_PAGE_SIZE) {
    throw databaseFailure("The export scan RPC exceeded its row bound.", value);
  }

  const scans: DBScanRow[] = [];
  let sourceByteCount = 0;
  let pageComplete: boolean | null = null;
  for (const rpcRow of rpcRows) {
    if (
      typeof rpcRow.scan_id !== "string" ||
      typeof rpcRow.source_byte_count !== "number" ||
      !Number.isSafeInteger(rpcRow.source_byte_count) ||
      rpcRow.source_byte_count < 1 ||
      rpcRow.source_byte_count > MAXIMUM_EXPORT_SOURCE_PAGE_BYTES ||
      typeof rpcRow.page_complete !== "boolean" ||
      rpcRow.source_row_oversize !== false
    ) {
      throw databaseFailure(
        "The export scan RPC returned a malformed row.",
        rpcRow,
      );
    }
    if (pageComplete !== null && rpcRow.page_complete !== pageComplete) {
      throw databaseFailure(
        "The export scan RPC returned inconsistent completion state.",
        value,
      );
    }
    pageComplete = rpcRow.page_complete;
    sourceByteCount += rpcRow.source_byte_count;
    if (sourceByteCount > MAXIMUM_EXPORT_SOURCE_PAGE_BYTES) {
      throw databaseFailure(
        "The export scan RPC exceeded its byte bound.",
        value,
      );
    }
    scans.push(
      parseExportScanPayload(
        rpcRow.scan_payload,
        rpcRow.scan_id,
        projection,
      ),
    );
  }

  return {
    scans,
    sourceByteCount,
    pageComplete: pageComplete ?? false,
  };
}

export async function fetchExportScanBatch(
  job: ClaimedExportJob,
  claimToken: string,
  projection: ExportProjection,
  afterId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<ExportScanBatch> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_dwca_export_scan_batch",
    {
      p_job_id: job.id,
      p_claim_token: claimToken,
      p_expected_phase: projection,
      p_after_id: afterId,
      p_max_rows: EXPORT_PAGE_SIZE,
      p_max_source_bytes: MAXIMUM_EXPORT_SOURCE_PAGE_BYTES,
    },
  );
  if (error) {
    if (error.code === "54000") {
      throw new ExportWorkerError(
        "export_too_large",
        "An export source row exceeded its canonical byte bound.",
      );
    }
    throw databaseFailure("Failed to fetch a bounded export scan page.", error);
  }
  return parseExportScanBatch(data, projection);
}
