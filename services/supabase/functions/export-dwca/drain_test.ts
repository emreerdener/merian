import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import { drainExportJobs, exportQueueHealthStatus } from "./drain.ts";
import {
  EXPORT_BACKLOG_CRITICAL_AGE_SECONDS,
  EXPORT_BACKLOG_CRITICAL_COUNT,
  EXPORT_BACKLOG_WARNING_AGE_SECONDS,
  EXPORT_BACKLOG_WARNING_COUNT,
  EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
} from "./limits.ts";
import { ExportQueueHealth, ExportWorkerError } from "./types.ts";

const unusedClient = {} as SupabaseClient;
const firstJob = "00000000-0000-4000-8000-000000000101";
const secondJob = "00000000-0000-4000-8000-000000000102";
const requestedJob = "00000000-0000-4000-8000-000000000103";

const HEALTHY_QUEUE: ExportQueueHealth = {
  generatedAt: "2026-07-26T22:00:00.000Z",
  backlogCount: 0,
  dueCount: 0,
  activeClaimCount: 0,
  expiredClaimCount: 0,
  oldestDueAt: null,
  oldestDueAgeSeconds: null,
};

Deno.test("drainExportJobs bounds a targeted insert wake-up to one job", async () => {
  const processOrder: string[] = [];
  const result = await drainExportJobs(
    unusedClient,
    requestedJob,
    {
      monotonicNow: () => 1,
      fetchDue: () => {
        throw new Error("A targeted wake-up must not fan out globally.");
      },
      processStep: (jobId) => {
        processOrder.push(jobId);
        return Promise.resolve({
          disposition: "advanced",
          phase: "occurrence",
        });
      },
      fetchHealth: () => Promise.resolve(HEALTHY_QUEUE),
    },
  );

  assertEquals(processOrder, [requestedJob]);
  assertEquals(result.targetedWakeup, true);
  assertEquals(result.attemptedSteps, 1);
  assertEquals(result.discoveryWaves, 0);
  assertEquals(result.runtimeDeadlineReached, false);
});

Deno.test("drainExportJobs drains fair scheduled due waves", async () => {
  const processOrder: string[] = [];
  const requestedLimits: number[] = [];
  const waves = [
    [firstJob, secondJob],
    [secondJob, firstJob],
    [],
  ];

  const result = await drainExportJobs(
    unusedClient,
    null,
    {
      monotonicNow: () => 1,
      fetchDue: (_client, limit) => {
        requestedLimits.push(limit ?? -1);
        return Promise.resolve(waves.shift() ?? []);
      },
      processStep: (jobId) => {
        processOrder.push(jobId);
        if (jobId === firstJob && processOrder.length === 4) {
          return Promise.resolve({
            disposition: "completed",
            phase: "completed",
          });
        }
        return Promise.resolve({
          disposition: "advanced",
          phase: "occurrence",
        });
      },
      fetchHealth: () => Promise.resolve(HEALTHY_QUEUE),
    },
  );

  assertEquals(processOrder, [
    firstJob,
    secondJob,
    secondJob,
    firstJob,
  ]);
  assertEquals(requestedLimits, [
    EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
    EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
    EXPORT_DRAIN_DISCOVERY_BATCH_SIZE,
  ]);
  assertEquals(result.targetedWakeup, false);
  assertEquals(result.attemptedSteps, 4);
  assertEquals(result.advancedSteps, 3);
  assertEquals(result.completedJobs, 1);
  assertEquals(result.discoveryWaves, 3);
  assertEquals(result.queueDrained, true);
  assertEquals(result.runtimeDeadlineReached, false);
  assertEquals(result.stepLimitReached, false);
});

Deno.test("drainExportJobs stops discovery at the soft runtime deadline", async () => {
  const times = [0, 1, 2, 40_000, 40_001];
  let processed = 0;
  const overdueQueue: ExportQueueHealth = {
    ...HEALTHY_QUEUE,
    backlogCount: 1,
    dueCount: 1,
    oldestDueAt: "2026-07-26T21:59:00.000Z",
    oldestDueAgeSeconds: 60,
  };

  const result = await drainExportJobs(
    unusedClient,
    null,
    {
      monotonicNow: () => times.shift() ?? 40_001,
      processStep: () => {
        processed += 1;
        return Promise.resolve({
          disposition: "advanced",
          phase: "occurrence",
        });
      },
      fetchDue: () => Promise.resolve([firstJob]),
      fetchHealth: () => Promise.resolve(overdueQueue),
    },
  );

  assertEquals(processed, 1);
  assertEquals(result.attemptedSteps, 1);
  assertEquals(result.queueDrained, false);
  assertEquals(result.runtimeDeadlineReached, true);
  assertEquals(result.stepLimitReached, false);
});

Deno.test("drainExportJobs does not start a step after slow discovery crosses the cutoff", async () => {
  const times = [0, 39_999, 40_000, 40_001];
  let processed = 0;
  const overdueQueue: ExportQueueHealth = {
    ...HEALTHY_QUEUE,
    backlogCount: 1,
    dueCount: 1,
    oldestDueAt: "2026-07-26T21:59:00.000Z",
    oldestDueAgeSeconds: 60,
  };

  const result = await drainExportJobs(
    unusedClient,
    null,
    {
      monotonicNow: () => times.shift() ?? 40_001,
      processStep: () => {
        processed += 1;
        return Promise.resolve({
          disposition: "advanced",
          phase: "occurrence",
        });
      },
      fetchDue: () => Promise.resolve([firstJob]),
      fetchHealth: () => Promise.resolve(overdueQueue),
    },
  );

  assertEquals(processed, 0);
  assertEquals(result.attemptedSteps, 0);
  assertEquals(result.queueDrained, false);
  assertEquals(result.runtimeDeadlineReached, true);
  assertEquals(result.stepLimitReached, false);
});

Deno.test("drainExportJobs does not hot-loop a failed or contended job", async () => {
  let attempts = 0;
  let discoveries = 0;
  let observedError: unknown;
  const failure = new ExportWorkerError(
    "database_unavailable",
    "Transient database failure.",
    true,
  );
  const result = await drainExportJobs(
    unusedClient,
    null,
    {
      monotonicNow: () => 1,
      processStep: () => {
        attempts += 1;
        throw failure;
      },
      fetchDue: () => {
        discoveries += 1;
        return Promise.resolve([requestedJob]);
      },
      fetchHealth: () => Promise.resolve(HEALTHY_QUEUE),
      onStep: (_step, error) => {
        observedError = error;
      },
    },
  );

  assertEquals(attempts, 1);
  assertEquals(discoveries, 2);
  assertEquals(observedError, failure);
  assertEquals(result.failedSteps, 1);
  assertEquals(result.steps, [{
    jobId: requestedJob,
    disposition: "failed",
    failureCode: "database_unavailable",
  }]);
});

Deno.test("drainExportJobs fails closed on invalid discovery responses", async () => {
  await assertRejects(
    () =>
      drainExportJobs(
        unusedClient,
        null,
        {
          monotonicNow: () => 1,
          fetchDue: () =>
            Promise.resolve(
              Array.from(
                { length: EXPORT_DRAIN_DISCOVERY_BATCH_SIZE + 1 },
                () => firstJob,
              ),
            ),
          fetchHealth: () => Promise.resolve(HEALTHY_QUEUE),
        },
      ),
    Error,
    "exceeded its requested batch size",
  );
});

Deno.test("exportQueueHealthStatus covers queue age, depth, and expired leases", () => {
  assertEquals(exportQueueHealthStatus(HEALTHY_QUEUE), "ok");
  assertEquals(
    exportQueueHealthStatus({
      ...HEALTHY_QUEUE,
      backlogCount: EXPORT_BACKLOG_WARNING_COUNT,
    }),
    "warning",
  );
  assertEquals(
    exportQueueHealthStatus({
      ...HEALTHY_QUEUE,
      backlogCount: EXPORT_BACKLOG_CRITICAL_COUNT,
    }),
    "critical",
  );
  assertEquals(
    exportQueueHealthStatus({
      ...HEALTHY_QUEUE,
      backlogCount: 1,
      dueCount: 1,
      oldestDueAt: "2026-07-26T21:55:00.000Z",
      oldestDueAgeSeconds: EXPORT_BACKLOG_WARNING_AGE_SECONDS,
    }),
    "warning",
  );
  assertEquals(
    exportQueueHealthStatus({
      ...HEALTHY_QUEUE,
      backlogCount: 1,
      dueCount: 1,
      oldestDueAt: "2026-07-26T21:45:00.000Z",
      oldestDueAgeSeconds: EXPORT_BACKLOG_CRITICAL_AGE_SECONDS,
    }),
    "critical",
  );
  assertEquals(
    exportQueueHealthStatus({
      ...HEALTHY_QUEUE,
      backlogCount: 1,
      expiredClaimCount: 1,
    }),
    "warning",
  );
});
