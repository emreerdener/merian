import { SupabaseClient } from "@supabase/supabase-js";
import { createDwcaArchiveStream } from "./archive.ts";
import {
  claimExportJob,
  completeExportJob,
  failExportJob,
  fetchUserEmail,
  renewExportJobClaim,
  stageExportJobArchive,
} from "./db.ts";
import { sendExportEmail } from "./mail.ts";
import { loadUserPseudonymizer, UserPseudonymizer } from "./pseudonym.ts";
import {
  exportObjectKey,
  ExportUploadResult,
  uploadDwcaArchive,
} from "./storage.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

const HEARTBEAT_INTERVAL_MS = 60_000;
const COMPLETION_RETRY_DELAYS_MS = [0, 100, 500] as const;

export interface ExportWorkerResult {
  disposition: "completed" | "not_claimed";
  attemptCount?: number;
  reusedArchive?: boolean;
  uploadedBytes?: number;
  uploadedParts?: number;
}

export interface ExportWorkerServices {
  claim(jobId: string, claimToken: string): Promise<ClaimedExportJob | null>;
  renew(jobId: string, claimToken: string): Promise<void>;
  fetchEmail(userId: string): Promise<string>;
  loadPseudonymizer(keyVersion: number): Promise<UserPseudonymizer>;
  createArchive(
    job: ClaimedExportJob,
    pseudonymizer: UserPseudonymizer | null,
    onProgress: () => Promise<void>,
  ): ReadableStream<Uint8Array>;
  uploadArchive(
    archive: ReadableStream<Uint8Array>,
    objectKey: string,
    onProgress: () => Promise<void>,
  ): Promise<ExportUploadResult>;
  stageArchive(
    jobId: string,
    claimToken: string,
    objectKey: string,
    signedUrl: string,
  ): Promise<void>;
  sendEmail(email: string, signedUrl: string, jobId: string): Promise<string>;
  complete(jobId: string, claimToken: string): Promise<void>;
  fail(
    jobId: string,
    claimToken: string,
    failureCode: string,
  ): Promise<boolean>;
  now(): number;
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
    fetchEmail: (userId) => fetchUserEmail(userId, supabaseAdmin),
    loadPseudonymizer: loadUserPseudonymizer,
    createArchive: (job, pseudonymizer, onProgress) =>
      createDwcaArchiveStream(
        job,
        supabaseAdmin,
        pseudonymizer,
        onProgress,
      ),
    uploadArchive: uploadDwcaArchive,
    stageArchive: (jobId, claimToken, objectKey, signedUrl) =>
      stageExportJobArchive(
        jobId,
        claimToken,
        objectKey,
        signedUrl,
        supabaseAdmin,
      ),
    sendEmail: sendExportEmail,
    complete: (jobId, claimToken) =>
      completeExportJob(jobId, claimToken, supabaseAdmin),
    fail: (jobId, claimToken, failureCode) =>
      failExportJob(jobId, claimToken, failureCode, supabaseAdmin),
    now: Date.now,
    sleep: (milliseconds) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)),
  };
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
      lastError = error;
    }
  }
  if (lastError instanceof Error) throw lastError;
  throw new ExportWorkerError(
    "database_unavailable",
    "The export completion could not be persisted.",
    false,
  );
}

function failureFrom(error: unknown): ExportWorkerError {
  if (error instanceof ExportWorkerError) return error;
  return new ExportWorkerError(
    "archive_generation_failed",
    "The export worker failed unexpectedly.",
    true,
    { cause: error },
  );
}

export async function processExportJob(
  jobId: string,
  supabaseAdmin: SupabaseClient,
  overrides: Partial<ExportWorkerServices> = {},
): Promise<ExportWorkerResult> {
  const services = { ...defaultServices(supabaseAdmin), ...overrides };
  const claimToken = crypto.randomUUID();
  const job = await services.claim(jobId, claimToken);
  if (!job) return { disposition: "not_claimed" };

  let lastHeartbeatAt = services.now();
  let deliveryAccepted = false;
  const heartbeat = async (force = false): Promise<void> => {
    const now = services.now();
    if (!force && now - lastHeartbeatAt < HEARTBEAT_INTERVAL_MS) return;
    await services.renew(job.id, claimToken);
    lastHeartbeatAt = now;
  };

  try {
    const email = await services.fetchEmail(job.userId);
    let objectKey = job.archiveObjectKey;
    let signedUrl = job.fileUrl;
    let reusedArchive = Boolean(
      objectKey && signedUrl && job.archiveReadyAt,
    );
    let uploadResult: ExportUploadResult | null = null;

    if (!reusedArchive) {
      objectKey = exportObjectKey(job, claimToken);
      const pseudonymizer = job.exportScope === "global"
        ? await services.loadPseudonymizer(job.pseudonymKeyVersion)
        : null;
      const archive = services.createArchive(
        job,
        pseudonymizer,
        heartbeat,
      );
      uploadResult = await services.uploadArchive(
        archive,
        objectKey,
        heartbeat,
      );
      signedUrl = uploadResult.signedUrl;
      await heartbeat(true);
      await services.stageArchive(
        job.id,
        claimToken,
        objectKey,
        signedUrl,
      );
      reusedArchive = false;
    }

    if (!objectKey || !signedUrl) {
      throw new ExportWorkerError(
        "archive_stage_failed",
        "The worker reached delivery without a staged archive.",
      );
    }

    await heartbeat(true);
    await services.sendEmail(email, signedUrl, job.id);
    deliveryAccepted = true;
    await retryCompletion(
      () => services.complete(job.id, claimToken),
      services,
    );

    return {
      disposition: "completed",
      attemptCount: job.attemptCount,
      reusedArchive,
      uploadedBytes: uploadResult?.uploadedBytes,
      uploadedParts: uploadResult?.uploadedParts,
    };
  } catch (error) {
    const failure = failureFrom(error);
    if (failure.safeToFailJob && !deliveryAccepted) {
      try {
        await services.fail(job.id, claimToken, failure.code);
      } catch (recordingError) {
        console.error(JSON.stringify({
          event: "dwca_export_failure_recording_failed",
          job_id: job.id,
          error: recordingError instanceof Error
            ? recordingError.message
            : String(recordingError),
          ts: new Date().toISOString(),
        }));
      }
    }
    throw failure;
  }
}
