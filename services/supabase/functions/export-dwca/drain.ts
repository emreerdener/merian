import { SupabaseClient } from "@supabase/supabase-js";
import { fetchDueExportJobIds, fetchExportQueueHealth } from "./db.ts";
import {
  EXPORT_BACKLOG_CRITICAL_AGE_SECONDS,
  EXPORT_BACKLOG_CRITICAL_COUNT,
  EXPORT_BACKLOG_WARNING_AGE_SECONDS,
  EXPORT_BACKLOG_WARNING_COUNT,
  EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
  EXPORT_DRAIN_FINAL_STEP_RESERVE_MS,
  EXPORT_DRAIN_MAXIMUM_STEPS,
  EXPORT_DRAIN_RUNTIME_BUDGET_MS,
} from "./limits.ts";
import {
  ExportQueueHealth,
  ExportWorkerError,
  ExportWorkPhase,
} from "./types.ts";
import { ExportWorkerResult, processExportJobStep } from "./worker.ts";

export type ExportQueueHealthStatus = "ok" | "warning" | "critical";

export interface ExportDrainStep {
  jobId: string;
  disposition: ExportWorkerResult["disposition"] | "failed";
  phase?: ExportWorkPhase;
  failureCode?: ExportWorkerError["code"];
}

export interface ExportDrainResult {
  targetedWakeup: boolean;
  attemptedSteps: number;
  advancedSteps: number;
  completedJobs: number;
  notClaimedSteps: number;
  failedSteps: number;
  discoveryWaves: number;
  queueDrained: boolean;
  runtimeDeadlineReached: boolean;
  stepLimitReached: boolean;
  healthStatus: ExportQueueHealthStatus;
  health: ExportQueueHealth;
  steps: ExportDrainStep[];
  elapsedMilliseconds: number;
}

interface ExportDrainDependencies {
  fetchDue?: typeof fetchDueExportJobIds;
  processStep?: typeof processExportJobStep;
  fetchHealth?: typeof fetchExportQueueHealth;
  monotonicNow?: () => number;
  onStep?: (step: ExportDrainStep, error?: unknown) => void;
}

function monotonicTime(clock: () => number): number {
  const value = clock();
  if (!Number.isFinite(value) || value < 0) {
    throw new Error("The export drain runtime clock is invalid.");
  }
  return value;
}

function failureCode(error: unknown): ExportWorkerError["code"] {
  return error instanceof ExportWorkerError
    ? error.code
    : "archive_generation_failed";
}

export function exportQueueHealthStatus(
  health: ExportQueueHealth,
): ExportQueueHealthStatus {
  const oldestDueAgeSeconds = health.oldestDueAgeSeconds ?? 0;
  if (
    oldestDueAgeSeconds >= EXPORT_BACKLOG_CRITICAL_AGE_SECONDS ||
    health.backlogCount >= EXPORT_BACKLOG_CRITICAL_COUNT
  ) {
    return "critical";
  }
  if (
    health.expiredClaimCount > 0 ||
    oldestDueAgeSeconds >= EXPORT_BACKLOG_WARNING_AGE_SECONDS ||
    health.backlogCount >= EXPORT_BACKLOG_WARNING_COUNT
  ) {
    return "warning";
  }
  return "ok";
}

export async function drainExportJobs(
  supabaseAdmin: SupabaseClient,
  requestedJobId: string | null = null,
  dependencies: ExportDrainDependencies = {},
): Promise<ExportDrainResult> {
  const fetchDue = dependencies.fetchDue ?? fetchDueExportJobIds;
  const processStep = dependencies.processStep ?? processExportJobStep;
  const fetchHealth = dependencies.fetchHealth ?? fetchExportQueueHealth;
  const clock = dependencies.monotonicNow ?? (() => performance.now());
  const startedAt = monotonicTime(clock);
  const discoveryCutoffAt = startedAt + EXPORT_DRAIN_RUNTIME_BUDGET_MS -
    EXPORT_DRAIN_FINAL_STEP_RESERVE_MS;
  const targetedWakeup = requestedJobId !== null;
  const candidates = requestedJobId === null ? [] : [requestedJobId];
  const suppressedJobIds = new Set<string>();
  const steps: ExportDrainStep[] = [];
  let advancedSteps = 0;
  let completedJobs = 0;
  let notClaimedSteps = 0;
  let failedSteps = 0;
  let discoveryWaves = 0;
  let discoveryDrained = false;

  while (
    steps.length < EXPORT_DRAIN_MAXIMUM_STEPS &&
    monotonicTime(clock) < discoveryCutoffAt
  ) {
    if (candidates.length === 0) {
      const dueJobIds = await fetchDue(
        supabaseAdmin,
        EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
      );
      discoveryWaves += 1;
      if (dueJobIds.length === 0) {
        discoveryDrained = true;
        break;
      }
      if (dueJobIds.length > EXPORT_DRAIN_DISCOVERY_BATCH_SIZE) {
        throw new Error(
          "The export due-job discovery exceeded its requested batch size.",
        );
      }
      const uniqueDueJobIds = [...new Set(dueJobIds)].filter(
        (jobId) => !suppressedJobIds.has(jobId),
      );
      if (uniqueDueJobIds.length === 0) break;
      candidates.push(...uniqueDueJobIds);
      // Discovery is an awaited database operation. Fence again before
      // starting a phase so a slow query that crossed the soft cutoff cannot
      // consume the final-step reserve.
      if (monotonicTime(clock) >= discoveryCutoffAt) break;
    }

    const jobId = candidates.shift();
    if (jobId === undefined) continue;

    let step: ExportDrainStep;
    let stepError: unknown;
    try {
      const result = await processStep(jobId, supabaseAdmin);
      step = {
        jobId,
        disposition: result.disposition,
        ...(result.phase === undefined ? {} : { phase: result.phase }),
      };
      if (result.disposition === "advanced") {
        advancedSteps += 1;
      } else if (result.disposition === "completed") {
        completedJobs += 1;
        suppressedJobIds.add(jobId);
      } else {
        notClaimedSteps += 1;
        suppressedJobIds.add(jobId);
      }
    } catch (error) {
      stepError = error;
      failedSteps += 1;
      suppressedJobIds.add(jobId);
      step = {
        jobId,
        disposition: "failed",
        failureCode: failureCode(error),
      };
    }
    steps.push(step);
    dependencies.onStep?.(step, stepError);
    // Insert webhooks can fan out under bursty intake. Keep each targeted
    // wake-up to its one canonical job; only the once-per-minute empty-body
    // dispatcher performs a global deadline drain.
    if (targetedWakeup) break;
  }

  const health = await fetchHealth(supabaseAdmin);
  const queueDrained = health.dueCount === 0;
  const currentTime = monotonicTime(clock);
  return {
    targetedWakeup,
    attemptedSteps: steps.length,
    advancedSteps,
    completedJobs,
    notClaimedSteps,
    failedSteps,
    discoveryWaves,
    queueDrained,
    runtimeDeadlineReached: !targetedWakeup &&
      !discoveryDrained &&
      !queueDrained &&
      currentTime >= discoveryCutoffAt,
    stepLimitReached: !queueDrained &&
      steps.length >= EXPORT_DRAIN_MAXIMUM_STEPS,
    healthStatus: exportQueueHealthStatus(health),
    health,
    steps,
    elapsedMilliseconds: Math.max(0, currentTime - startedAt),
  };
}
