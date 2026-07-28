import type { SupabaseClient } from "@supabase/supabase-js";
import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import { collectScanMediaUrls } from "../_shared/scanMediaDeletion.ts";
import {
  completeScanDeletion,
  type DBScanRow,
  fetchScanRecord,
} from "../delete-scan/db.ts";
import {
  type ClaimedScanDeletion,
  claimScanDeletionJobs,
  getScanDeletionHealth,
  releaseScanDeletionJob,
  type ScanDeletionHealth,
} from "./db.ts";

const CLAIM_BATCH_SIZE = 25;
const MAXIMUM_JOBS_PER_INVOCATION = 100;
const DELETE_CONCURRENCY = 4;
const RUNTIME_BUDGET_MS = 40_000;

export interface ScanDeletionReconciliationResult {
  claimed: number;
  completed: number;
  deferred: number;
  runtimeDeadlineReached: boolean;
  health: ScanDeletionHealth;
  healthStatus: "healthy" | "warning" | "critical";
}

export interface ScanDeletionReconciliationServices {
  claim(token: string, limit: number): Promise<ClaimedScanDeletion[]>;
  loadScan(scanId: string): Promise<DBScanRow | null>;
  deleteMedia(urls: string[], ownerUserId: string): Promise<void>;
  complete(scanId: string, userId: string): Promise<void>;
  release(
    scanId: string,
    userId: string,
    token: string,
    errorCode: string,
  ): Promise<void>;
  health(): Promise<ScanDeletionHealth>;
  now(): number;
}

export async function reconcileScanDeletions(
  supabaseAdmin: SupabaseClient,
  overrides: Partial<ScanDeletionReconciliationServices> = {},
): Promise<ScanDeletionReconciliationResult> {
  const services: ScanDeletionReconciliationServices = {
    claim: (token, limit) => claimScanDeletionJobs(token, limit, supabaseAdmin),
    loadScan: (scanId) => fetchScanRecord(scanId, supabaseAdmin),
    deleteMedia: (urls, ownerUserId) =>
      urls.length === 0
        ? Promise.resolve()
        : deleteScanMediaR2Objects(urls, ownerUserId, getR2Config()),
    complete: (scanId, userId) =>
      completeScanDeletion(scanId, userId, supabaseAdmin),
    release: (scanId, userId, token, errorCode) =>
      releaseScanDeletionJob(
        scanId,
        userId,
        token,
        errorCode,
        supabaseAdmin,
      ),
    health: () => getScanDeletionHealth(supabaseAdmin),
    now: Date.now,
    ...overrides,
  };

  const claimToken = crypto.randomUUID();
  const deadline = services.now() + RUNTIME_BUDGET_MS;
  let claimed = 0;
  let completed = 0;
  let deferred = 0;
  let runtimeDeadlineReached = false;

  while (claimed < MAXIMUM_JOBS_PER_INVOCATION) {
    if (services.now() >= deadline) {
      runtimeDeadlineReached = true;
      break;
    }
    const jobs = await services.claim(
      claimToken,
      Math.min(CLAIM_BATCH_SIZE, MAXIMUM_JOBS_PER_INVOCATION - claimed),
    );
    if (jobs.length === 0) break;
    claimed += jobs.length;

    const outcomes = await mapWithConcurrencyLimit(
      jobs,
      DELETE_CONCURRENCY,
      async (job) => {
        try {
          const scan = await services.loadScan(job.scanId);
          if (
            scan?.user_id !== null &&
            scan?.user_id !== undefined &&
            scan.user_id !== job.userId
          ) {
            throw new Error("Scan deletion owner fence changed.");
          }
          await services.deleteMedia(
            scan === null ? [] : collectScanMediaUrls(scan),
            job.userId,
          );
          await services.complete(job.scanId, job.userId);
          return true;
        } catch (error) {
          console.warn(JSON.stringify({
            event: "scan_deletion_deferred",
            attempt_count: job.attemptCount,
            error: error instanceof Error ? error.name : typeof error,
            ts: new Date().toISOString(),
          }));
          try {
            await services.release(
              job.scanId,
              job.userId,
              claimToken,
              "scan_deletion_failed",
            );
          } catch (releaseError) {
            console.error(JSON.stringify({
              event: "scan_deletion_release_failed",
              error: releaseError instanceof Error
                ? releaseError.name
                : typeof releaseError,
              ts: new Date().toISOString(),
            }));
          }
          return false;
        }
      },
    );
    completed += outcomes.filter(Boolean).length;
    deferred += outcomes.filter((outcome) => !outcome).length;
  }

  const health = await services.health();
  return {
    claimed,
    completed,
    deferred,
    runtimeDeadlineReached,
    health,
    healthStatus: classifyScanDeletionHealth(health),
  };
}

export function classifyScanDeletionHealth(
  health: ScanDeletionHealth,
): "healthy" | "warning" | "critical" {
  if (
    health.expiredLeaseCount > 0 ||
    health.pendingCount >= 100 ||
    (health.oldestPendingAgeSeconds ?? 0) >= 60 * 60
  ) {
    return "critical";
  }
  if (
    health.pendingCount >= 25 ||
    (health.oldestPendingAgeSeconds ?? 0) >= 15 * 60
  ) {
    return "warning";
  }
  return "healthy";
}
