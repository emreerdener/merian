import type { SupabaseClient } from "@supabase/supabase-js";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import { deleteDwcaArchiveObject } from "../export-dwca/storage.ts";
import {
  claimDwcaArchiveCleanupJobs,
  ClaimedDwcaArchiveCleanup,
  completeDwcaArchiveCleanupJob,
  DwcaArchiveCleanupHealth,
  getDwcaArchiveCleanupHealth,
  releaseDwcaArchiveCleanupJob,
} from "./db.ts";

const CLAIM_BATCH_SIZE = 25;
const MAXIMUM_JOBS_PER_INVOCATION = 100;
const DELETE_CONCURRENCY = 4;
const RUNTIME_BUDGET_MS = 40_000;

export interface DwcaArchiveCleanupResult {
  claimed: number;
  completed: number;
  deferred: number;
  runtimeDeadlineReached: boolean;
  health: DwcaArchiveCleanupHealth;
  healthStatus: "healthy" | "warning" | "critical";
}

export interface DwcaArchiveCleanupServices {
  claim(token: string, limit: number): Promise<ClaimedDwcaArchiveCleanup[]>;
  deleteObject(objectKey: string): Promise<void>;
  complete(cleanupId: string, token: string): Promise<void>;
  release(
    cleanupId: string,
    token: string,
    errorCode: string,
  ): Promise<void>;
  health(): Promise<DwcaArchiveCleanupHealth>;
  now(): number;
}

export async function reconcileDwcaArchiveCleanup(
  supabaseAdmin: SupabaseClient,
  overrides: Partial<DwcaArchiveCleanupServices> = {},
): Promise<DwcaArchiveCleanupResult> {
  const services: DwcaArchiveCleanupServices = {
    claim: (token, limit) =>
      claimDwcaArchiveCleanupJobs(token, limit, supabaseAdmin),
    deleteObject: deleteDwcaArchiveObject,
    complete: (cleanupId, token) =>
      completeDwcaArchiveCleanupJob(cleanupId, token, supabaseAdmin),
    release: (cleanupId, token, errorCode) =>
      releaseDwcaArchiveCleanupJob(
        cleanupId,
        token,
        errorCode,
        supabaseAdmin,
      ),
    health: () => getDwcaArchiveCleanupHealth(supabaseAdmin),
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
          await services.deleteObject(job.objectKey);
          await services.complete(job.cleanupId, claimToken);
          return true;
        } catch (error) {
          console.warn(JSON.stringify({
            event: "dwca_archive_cleanup_deferred",
            cleanup_id: job.cleanupId,
            attempt_count: job.attemptCount,
            error: error instanceof Error ? error.name : typeof error,
            ts: new Date().toISOString(),
          }));
          try {
            await services.release(
              job.cleanupId,
              claimToken,
              "archive_delete_failed",
            );
          } catch (releaseError) {
            console.error(JSON.stringify({
              event: "dwca_archive_cleanup_release_failed",
              cleanup_id: job.cleanupId,
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
    healthStatus: classifyDwcaArchiveCleanupHealth(health),
  };
}

export function classifyDwcaArchiveCleanupHealth(
  health: DwcaArchiveCleanupHealth,
): "healthy" | "warning" | "critical" {
  if (
    health.expiredLeaseCount > 0 ||
    health.pendingCount >= 100 ||
    (health.oldestDueAgeSeconds ?? 0) >= 60 * 60
  ) {
    return "critical";
  }
  if (
    health.pendingCount >= 25 ||
    (health.oldestDueAgeSeconds ?? 0) >= 15 * 60
  ) {
    return "warning";
  }
  return "healthy";
}
