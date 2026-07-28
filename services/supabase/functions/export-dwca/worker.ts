import { SupabaseClient } from "@supabase/supabase-js";
import {
  createPreparedDwcaArchiveStream,
  EncodedExportBatch,
  encodeExportBatch,
} from "./archive.ts";
import {
  advanceExportJobStep,
  checkExportSourceFence,
  claimExportJob,
  completePreparedExportJob,
  fetchExportJobChunks,
  fetchExportScanBatch,
  fetchUserEmail,
  releaseExportJobStep,
  renewExportJobClaim,
  stagePreparedExportArchive,
} from "./db.ts";
import { sendExportEmail } from "./mail.ts";
import { loadUserPseudonymizer, UserPseudonymizer } from "./pseudonym.ts";
import {
  deleteDwcaArchiveObject,
  exportObjectKey,
  ExportUploadResult,
  exportWorkChunkObjectKey,
  putExportWorkChunk,
  uploadDwcaArchive,
} from "./storage.ts";
import {
  EXPORT_PAGE_SIZE,
  MAXIMUM_EXPORT_SOURCE_PAGE_BYTES,
  MAXIMUM_WORK_CHUNK_BYTES,
} from "./limits.ts";
import {
  ClaimedExportJob,
  DBScanRow,
  ExportChunkManifestEntry,
  ExportScanBatch,
  ExportWorkerError,
  ExportWorkPhase,
} from "./types.ts";

const COMPLETION_RETRY_DELAYS_MS = [0, 100, 500] as const;
const TERMINAL_FAILURE_CODES = new Set([
  "export_too_large",
  "pseudonym_key_unavailable",
  "source_snapshot_changed",
]);

export interface ExportWorkerResult {
  disposition: "advanced" | "completed" | "not_claimed";
  phase?: ExportWorkPhase;
  rowCount?: number;
  uploadedBytes?: number;
  uploadedParts?: number;
}

export interface ExportWorkerServices {
  claim(jobId: string, claimToken: string): Promise<ClaimedExportJob | null>;
  renew(jobId: string, claimToken: string): Promise<void>;
  fetchBatch(
    job: ClaimedExportJob,
    claimToken: string,
    phase: "occurrence" | "multimedia",
    afterId: string | null,
  ): Promise<ExportScanBatch>;
  loadPseudonymizer(keyVersion: number): Promise<UserPseudonymizer>;
  encodeBatch(
    job: ClaimedExportJob,
    phase: "occurrence" | "multimedia",
    scans: DBScanRow[],
    pseudonymizer: UserPseudonymizer | null,
  ): Promise<EncodedExportBatch>;
  putChunk(bytes: Uint8Array, objectKey: string): Promise<void>;
  advance(
    job: ClaimedExportJob,
    claimToken: string,
    phase: "occurrence" | "multimedia",
    nextAfterId: string | null,
    rowCount: number,
    objectKey: string,
    byteCount: number,
    crc32: number,
    pageComplete: boolean,
  ): Promise<ExportWorkPhase>;
  fetchManifest(
    jobId: string,
    claimToken: string,
  ): Promise<ExportChunkManifestEntry[]>;
  checkSource(
    jobId: string,
    claimToken: string,
    phase: "assembling" | "delivering",
  ): Promise<void>;
  createArchive(
    manifest: ExportChunkManifestEntry[],
    onProgress: () => Promise<void>,
  ): ReadableStream<Uint8Array>;
  uploadArchive(
    archive: ReadableStream<Uint8Array>,
    objectKey: string,
    onProgress: () => Promise<void>,
    maximumBytes: number,
  ): Promise<ExportUploadResult>;
  deleteArchive(objectKey: string): Promise<void>;
  stageArchive(
    jobId: string,
    claimToken: string,
    objectKey: string,
    signedUrl: string,
  ): Promise<void>;
  fetchEmail(userId: string): Promise<string>;
  sendEmail(email: string, signedUrl: string, jobId: string): Promise<string>;
  complete(jobId: string, claimToken: string): Promise<void>;
  release(
    jobId: string,
    claimToken: string,
    failureCode: string,
    terminal: boolean,
  ): Promise<boolean>;
  sleep(milliseconds: number): Promise<void>;
}

function defaultServices(
  supabaseAdmin: SupabaseClient,
): ExportWorkerServices {
  return {
    claim: (jobId, claimToken) =>
      claimExportJob(jobId, claimToken, supabaseAdmin),
    renew: (jobId, claimToken) =>
      renewExportJobClaim(jobId, claimToken, supabaseAdmin),
    fetchBatch: (job, claimToken, phase, afterId) =>
      fetchExportScanBatch(
        job,
        claimToken,
        phase,
        afterId,
        supabaseAdmin,
      ),
    loadPseudonymizer: loadUserPseudonymizer,
    encodeBatch: encodeExportBatch,
    putChunk: putExportWorkChunk,
    advance: (
      job,
      claimToken,
      phase,
      nextAfterId,
      rowCount,
      objectKey,
      byteCount,
      crc32,
      pageComplete,
    ) =>
      advanceExportJobStep(
        job,
        claimToken,
        phase,
        nextAfterId,
        rowCount,
        objectKey,
        byteCount,
        crc32,
        pageComplete,
        supabaseAdmin,
      ),
    fetchManifest: (jobId, claimToken) =>
      fetchExportJobChunks(jobId, claimToken, supabaseAdmin),
    checkSource: (jobId, claimToken, phase) =>
      checkExportSourceFence(
        jobId,
        claimToken,
        phase,
        supabaseAdmin,
      ),
    createArchive: createPreparedDwcaArchiveStream,
    uploadArchive: (
      archive,
      objectKey,
      onProgress,
      maximumBytes,
    ) =>
      uploadDwcaArchive(
        archive,
        objectKey,
        onProgress,
        undefined,
        maximumBytes,
      ),
    deleteArchive: deleteDwcaArchiveObject,
    stageArchive: (jobId, claimToken, objectKey, signedUrl) =>
      stagePreparedExportArchive(
        jobId,
        claimToken,
        objectKey,
        signedUrl,
        supabaseAdmin,
      ),
    fetchEmail: (userId) => fetchUserEmail(userId, supabaseAdmin),
    sendEmail: sendExportEmail,
    complete: (jobId, claimToken) =>
      completePreparedExportJob(jobId, claimToken, supabaseAdmin),
    release: (jobId, claimToken, failureCode, terminal) =>
      releaseExportJobStep(
        jobId,
        claimToken,
        failureCode,
        terminal,
        supabaseAdmin,
      ),
    sleep: (milliseconds) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)),
  };
}

function failureFrom(error: unknown): ExportWorkerError {
  if (error instanceof ExportWorkerError) return error;
  return new ExportWorkerError(
    "archive_generation_failed",
    "The export worker failed unexpectedly.",
    false,
    { cause: error },
  );
}

function validateBatch(
  batch: ExportScanBatch,
  afterId: string | null,
): void {
  if (
    !batch ||
    typeof batch !== "object" ||
    !Array.isArray(batch.scans) ||
    batch.scans.length > EXPORT_PAGE_SIZE ||
    !Number.isSafeInteger(batch.sourceByteCount) ||
    batch.sourceByteCount < 0 ||
    batch.sourceByteCount > MAXIMUM_EXPORT_SOURCE_PAGE_BYTES ||
    typeof batch.pageComplete !== "boolean" ||
    (batch.scans.length === 0 && !batch.pageComplete)
  ) {
    throw new ExportWorkerError(
      "database_unavailable",
      "The export batch exceeded its fixed source bounds.",
      false,
    );
  }
  let previousId = afterId;
  for (const scan of batch.scans) {
    if (
      typeof scan.id !== "string" ||
      scan.id.length === 0 ||
      (previousId !== null && scan.id <= previousId)
    ) {
      throw new ExportWorkerError(
        "database_unavailable",
        "The export batch was not a monotonic keyset page.",
        false,
      );
    }
    previousId = scan.id;
  }
}

async function retryCompletion(
  operation: () => Promise<void>,
  services: ExportWorkerServices,
): Promise<void> {
  let lastError: unknown;
  for (const delay of COMPLETION_RETRY_DELAYS_MS) {
    if (delay > 0) await services.sleep(delay);
    try {
      await operation();
      return;
    } catch (error) {
      if (
        error instanceof ExportWorkerError &&
        error.code === "source_snapshot_changed"
      ) {
        throw error;
      }
      lastError = error;
    }
  }
  throw failureFrom(lastError);
}

async function processPreparationStep(
  job: ClaimedExportJob,
  claimToken: string,
  services: ExportWorkerServices,
): Promise<ExportWorkerResult> {
  const phase = job.workPhase;
  if (phase !== "occurrence" && phase !== "multimedia") {
    throw new TypeError("Preparation requires a CSV phase.");
  }
  const afterId = phase === "occurrence"
    ? job.occurrenceAfterId
    : job.multimediaAfterId;
  const sourceBatch = await services.fetchBatch(
    job,
    claimToken,
    phase,
    afterId,
  );
  validateBatch(sourceBatch, afterId);
  const scans = sourceBatch.scans;
  const pseudonymizer = phase === "occurrence" && job.exportScope === "global"
    ? await services.loadPseudonymizer(job.pseudonymKeyVersion)
    : null;
  const batch = await services.encodeBatch(
    job,
    phase,
    scans,
    pseudonymizer,
  );
  if (
    !(batch.bytes instanceof Uint8Array) ||
    !Number.isSafeInteger(batch.rowCount) ||
    batch.rowCount < 0 ||
    !Number.isSafeInteger(batch.crc32) ||
    batch.crc32 < 0 ||
    batch.crc32 > 0xffff_ffff ||
    (batch.bytes.byteLength === 0 && batch.crc32 !== 0)
  ) {
    throw new ExportWorkerError(
      "archive_generation_failed",
      "The CSV encoder returned invalid durable integrity metadata.",
      false,
    );
  }
  if (
    batch.bytes.byteLength > MAXIMUM_WORK_CHUNK_BYTES ||
    job.occurrenceRows + job.multimediaRows + batch.rowCount >
      job.maxExportRows ||
    job.csvBytes + batch.bytes.byteLength > job.maxArchiveBytes - 65_536
  ) {
    throw new ExportWorkerError(
      "export_too_large",
      "The export exceeded its canonical row or byte budget.",
    );
  }
  // The claim token is part of the temporary key. If this lease expires after
  // PUT but before the fenced database advance, a replacement step writes a
  // different object and its committed manifest cannot be corrupted by the
  // delayed worker.
  const objectKey = exportWorkChunkObjectKey(job, phase, claimToken);
  await services.putChunk(batch.bytes, objectKey);
  const nextAfterId = scans.length > 0 ? scans[scans.length - 1].id : afterId;
  const nextPhase = await services.advance(
    job,
    claimToken,
    phase,
    nextAfterId,
    batch.rowCount,
    objectKey,
    batch.bytes.byteLength,
    batch.crc32,
    sourceBatch.pageComplete,
  );
  return {
    disposition: "advanced",
    phase: nextPhase,
    rowCount: batch.rowCount,
  };
}

async function processAssemblyStep(
  job: ClaimedExportJob,
  claimToken: string,
  services: ExportWorkerServices,
): Promise<ExportWorkerResult> {
  await services.checkSource(job.id, claimToken, "assembling");
  const manifest = await services.fetchManifest(job.id, claimToken);
  const manifestBytes = manifest.reduce(
    (total, chunk) => total + chunk.byteCount,
    0,
  );
  if (
    manifestBytes !== job.csvBytes ||
    manifestBytes > job.maxArchiveBytes - 65_536
  ) {
    throw new ExportWorkerError(
      "archive_generation_failed",
      "The prepared export manifest did not match durable budget state.",
      false,
    );
  }

  const heartbeat = () => services.renew(job.id, claimToken);
  const archive = services.createArchive(manifest, heartbeat);
  const objectKey = exportObjectKey(job, claimToken);
  const uploaded = await services.uploadArchive(
    archive,
    objectKey,
    heartbeat,
    job.maxArchiveBytes,
  );
  try {
    await services.stageArchive(
      job.id,
      claimToken,
      objectKey,
      uploaded.signedUrl,
    );
  } catch (error) {
    try {
      await services.deleteArchive(objectKey);
    } catch (deleteError) {
      console.error(JSON.stringify({
        event: "dwca_unstaged_archive_delete_failed",
        job_id: job.id,
        object_key: objectKey,
        error: deleteError instanceof Error
          ? deleteError.message
          : String(deleteError),
        ts: new Date().toISOString(),
      }));
    }
    throw error;
  }
  return {
    disposition: "advanced",
    phase: "delivering",
    uploadedBytes: uploaded.uploadedBytes,
    uploadedParts: uploaded.uploadedParts,
  };
}

async function processDeliveryStep(
  job: ClaimedExportJob,
  claimToken: string,
  services: ExportWorkerServices,
): Promise<ExportWorkerResult> {
  if (!job.archiveObjectKey || !job.fileUrl || !job.archiveReadyAt) {
    throw new ExportWorkerError(
      "archive_stage_failed",
      "Delivery requires a durably staged archive.",
      false,
    );
  }
  let email: string;
  try {
    await services.checkSource(job.id, claimToken, "delivering");
    email = await services.fetchEmail(job.userId);
    // Email lookup is an external suspension point. Re-run the full membership
    // fence immediately before the irreversible provider call rather than
    // relying on the check that preceded the lookup.
    await services.checkSource(job.id, claimToken, "delivering");
  } catch (error) {
    if (
      error instanceof ExportWorkerError &&
      error.code === "source_snapshot_changed"
    ) {
      await services.deleteArchive(job.archiveObjectKey);
    }
    throw error;
  }
  await services.sendEmail(email, job.fileUrl, job.id);
  try {
    await retryCompletion(
      () => services.complete(job.id, claimToken),
      services,
    );
  } catch (error) {
    if (
      error instanceof ExportWorkerError &&
      error.code === "source_snapshot_changed"
    ) {
      await services.deleteArchive(job.archiveObjectKey);
    }
    throw error;
  }
  return { disposition: "completed", phase: "completed" };
}

export async function processExportJobStep(
  jobId: string,
  supabaseAdmin: SupabaseClient,
  overrides: Partial<ExportWorkerServices> = {},
): Promise<ExportWorkerResult> {
  const services = { ...defaultServices(supabaseAdmin), ...overrides };
  const claimToken = crypto.randomUUID();
  const job = await services.claim(jobId, claimToken);
  if (!job) return { disposition: "not_claimed" };

  try {
    switch (job.workPhase) {
      case "occurrence":
      case "multimedia":
        return await processPreparationStep(job, claimToken, services);
      case "assembling":
        return await processAssemblyStep(job, claimToken, services);
      case "delivering":
        return await processDeliveryStep(job, claimToken, services);
      case "completed":
        return { disposition: "completed", phase: "completed" };
    }
  } catch (error) {
    const failure = failureFrom(error);
    const terminal = TERMINAL_FAILURE_CODES.has(failure.code);
    try {
      await services.release(
        job.id,
        claimToken,
        failure.code,
        terminal,
      );
    } catch (releaseError) {
      console.error(JSON.stringify({
        event: "dwca_export_step_release_failed",
        job_id: job.id,
        failure_code: failure.code,
        error: releaseError instanceof Error
          ? releaseError.message
          : String(releaseError),
        ts: new Date().toISOString(),
      }));
    }
    throw failure;
  }
}
