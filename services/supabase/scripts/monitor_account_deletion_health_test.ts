import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  type AccountDeletionHealth,
  type AccountDeletionRecoveryHealth,
  type AccountDeletionRecoveryPreparationHealth,
  accountDeletionStatus,
  assertAccountDeletionHealth,
  assertAccountDeletionRecoveryHealth,
  assertAccountDeletionRecoveryPreparationHealth,
  buildAccountDeletionSummary,
  parseAccountDeletionMonitorArgs,
  renderAccountDeletionMarkdown,
  resolveAccountDeletionRecoveryHealthRpcResult,
  resolveAccountDeletionRecoveryPreparationHealthRpcResult,
  shouldFailAccountDeletionMonitor,
} from "./monitor_account_deletion_health.ts";

const HEALTHY: AccountDeletionHealth = {
  generated_at: "2026-07-27T01:00:00.000Z",
  active_job_count: 0,
  pending_cleanup_count: 0,
  storage_pending_count: 0,
  auth_pending_count: 0,
  due_job_count: 0,
  failed_job_count: 0,
  active_lease_count: 0,
  expired_lease_count: 0,
  oldest_pending_at: null,
  oldest_pending_age_seconds: null,
  oldest_due_at: null,
  oldest_due_age_seconds: null,
  storage_backlog_count: 0,
  storage_due_count: 0,
  storage_failed_job_count: 0,
  storage_active_lease_count: 0,
  storage_expired_lease_count: 0,
  verification_waiting_count: 0,
  orphaned_storage_job_count: 0,
  oldest_storage_pending_at: null,
  oldest_storage_pending_age_seconds: null,
  oldest_storage_due_at: null,
  oldest_storage_due_age_seconds: null,
  reaper_cron_active: true,
  reaper_credentials_configured: true,
};

const RECOVERY_HEALTHY: AccountDeletionRecoveryHealth = {
  generated_at: "2026-07-27T01:00:00.000Z",
  active_unacknowledged_count: 0,
  acknowledged_retained_count: 0,
  expired_unacknowledged_count: 0,
  oldest_active_issued_at: null,
  oldest_active_age_seconds: null,
  oldest_expired_at: null,
  oldest_expired_age_seconds: null,
  maximum_active_capabilities_per_job: 0,
};

const PREPARATION_HEALTHY: AccountDeletionRecoveryPreparationHealth = {
  generated_at: "2026-07-27T01:00:00.000Z",
  active_preparation_count: 0,
  expired_preparation_count: 0,
  oldest_active_age_seconds: null,
  oldest_expired_age_seconds: null,
};

Deno.test("parseAccountDeletionMonitorArgs applies deletion SLA defaults", () => {
  assertEquals(parseAccountDeletionMonitorArgs([]), {
    warningDueAfterMinutes: 10,
    criticalDueAfterMinutes: 30,
    warningSlaHours: 27,
    criticalSlaHours: 36,
    warningBacklog: 25,
    criticalBacklog: 100,
    failOn: "warning",
    recoveryHealthMode: "required",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });
  assertEquals(
    parseAccountDeletionMonitorArgs([
      "--warning-due-after-minutes=15",
      "--critical-due-after-minutes",
      "60",
      "--warning-sla-hours",
      "30",
      "--critical-sla-hours=48",
      "--warning-backlog",
      "50",
      "--critical-backlog=250",
      "--fail-on",
      "critical",
      "--recovery-health-mode",
      "expand-compatible",
      "--summary-json=/tmp/account-deletion.json",
      "--summary-md",
      "/tmp/account-deletion.md",
    ]),
    {
      warningDueAfterMinutes: 15,
      criticalDueAfterMinutes: 60,
      warningSlaHours: 30,
      criticalSlaHours: 48,
      warningBacklog: 50,
      criticalBacklog: 250,
      failOn: "critical",
      recoveryHealthMode: "expand-compatible",
      summaryJsonPath: "/tmp/account-deletion.json",
      summaryMarkdownPath: "/tmp/account-deletion.md",
    },
  );
});

Deno.test("parseAccountDeletionMonitorArgs rejects unsafe thresholds", () => {
  assertThrows(() =>
    parseAccountDeletionMonitorArgs([
      "--warning-due-after-minutes",
      "30",
      "--critical-due-after-minutes",
      "30",
    ])
  );
  assertThrows(() =>
    parseAccountDeletionMonitorArgs([
      "--warning-sla-hours",
      "36",
      "--critical-sla-hours",
      "36",
    ])
  );
  assertThrows(() =>
    parseAccountDeletionMonitorArgs([
      "--warning-backlog",
      "100",
      "--critical-backlog",
      "100",
    ])
  );
  assertThrows(() => parseAccountDeletionMonitorArgs(["--fail-on", "always"]));
  assertThrows(() =>
    parseAccountDeletionMonitorArgs([
      "--recovery-health-mode",
      "optional",
    ])
  );
  assertThrows(() => parseAccountDeletionMonitorArgs(["--unknown", "1"]));
});

Deno.test("recovery health compatibility accepts only exact additive RPC absence", () => {
  const missingRecovery = {
    code: "PGRST202",
    message:
      "Could not find the function public.get_account_deletion_recovery_health without parameters in the schema cache",
  };
  const missingPreparation = {
    code: "PGRST202",
    message:
      "Could not find the function public.get_account_deletion_recovery_preparation_health without parameters in the schema cache",
  };

  assertEquals(
    resolveAccountDeletionRecoveryHealthRpcResult(
      null,
      missingRecovery,
      "expand-compatible",
    ),
    null,
  );
  assertEquals(
    resolveAccountDeletionRecoveryPreparationHealthRpcResult(
      null,
      missingPreparation,
      "expand-compatible",
    ),
    null,
  );
  assertThrows(() =>
    resolveAccountDeletionRecoveryHealthRpcResult(
      null,
      missingRecovery,
      "required",
    )
  );
  assertThrows(() =>
    resolveAccountDeletionRecoveryPreparationHealthRpcResult(
      null,
      { ...missingPreparation, code: "42501" },
      "expand-compatible",
    )
  );
  assertThrows(() =>
    resolveAccountDeletionRecoveryHealthRpcResult(
      null,
      {
        code: "PGRST202",
        message:
          "Could not find the function public.unrelated without parameters in the schema cache",
      },
      "expand-compatible",
    )
  );
});

Deno.test("assertAccountDeletionHealth validates one consistent summary", () => {
  const active: AccountDeletionHealth = {
    ...HEALTHY,
    active_job_count: 3,
    pending_cleanup_count: 1,
    storage_pending_count: 1,
    auth_pending_count: 1,
    due_job_count: 1,
    failed_job_count: 1,
    active_lease_count: 1,
    expired_lease_count: 1,
    oldest_pending_at: "2026-07-26T00:00:00.000Z",
    oldest_pending_age_seconds: 90_000,
    oldest_due_at: "2026-07-27T00:45:00.000Z",
    oldest_due_age_seconds: 900,
    storage_backlog_count: 1,
    storage_due_count: 0,
    storage_failed_job_count: 1,
    storage_active_lease_count: 0,
    storage_expired_lease_count: 1,
    verification_waiting_count: 0,
    orphaned_storage_job_count: 0,
    oldest_storage_pending_at: "2026-07-26T00:00:00.000Z",
    oldest_storage_pending_age_seconds: 90_000,
  };
  assertEquals(assertAccountDeletionHealth([active]), active);
  assertThrows(() => assertAccountDeletionHealth([]));
  assertThrows(() => assertAccountDeletionHealth([null]));
  assertThrows(() =>
    assertAccountDeletionHealth([{
      ...HEALTHY,
      active_job_count: 1,
    }])
  );
  assertThrows(() =>
    assertAccountDeletionHealth([{
      ...HEALTHY,
      storage_backlog_count: 1,
      storage_due_count: 2,
    }])
  );
});

Deno.test("assertAccountDeletionRecoveryHealth validates aggregate-only state", () => {
  const active: AccountDeletionRecoveryHealth = {
    ...RECOVERY_HEALTHY,
    active_unacknowledged_count: 2,
    acknowledged_retained_count: 1,
    expired_unacknowledged_count: 1,
    oldest_active_issued_at: "2026-07-26T00:00:00.000Z",
    oldest_active_age_seconds: 90_000,
    oldest_expired_at: "2026-07-25T00:00:00.000Z",
    oldest_expired_age_seconds: 176_400,
    maximum_active_capabilities_per_job: 2,
  };
  assertEquals(assertAccountDeletionRecoveryHealth([active]), active);
  assertThrows(() => assertAccountDeletionRecoveryHealth([]));
  assertThrows(() =>
    assertAccountDeletionRecoveryHealth([{
      ...RECOVERY_HEALTHY,
      active_unacknowledged_count: 1,
    }])
  );
  assertThrows(() =>
    assertAccountDeletionRecoveryHealth([{
      ...RECOVERY_HEALTHY,
      maximum_active_capabilities_per_job: 1,
    }])
  );
});

Deno.test("assertAccountDeletionRecoveryPreparationHealth validates aggregate-only state", () => {
  const active: AccountDeletionRecoveryPreparationHealth = {
    ...PREPARATION_HEALTHY,
    active_preparation_count: 2,
    expired_preparation_count: 1,
    oldest_active_age_seconds: 120,
    oldest_expired_age_seconds: 30,
  };
  assertEquals(
    assertAccountDeletionRecoveryPreparationHealth([active]),
    active,
  );
  assertThrows(() => assertAccountDeletionRecoveryPreparationHealth([]));
  assertThrows(() =>
    assertAccountDeletionRecoveryPreparationHealth([{
      ...PREPARATION_HEALTHY,
      active_preparation_count: 1,
    }])
  );
});

Deno.test("accountDeletionStatus alerts on configuration and job health", () => {
  const args = parseAccountDeletionMonitorArgs([]);
  assertEquals(accountDeletionStatus(HEALTHY, args), "ok");
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, reaper_credentials_configured: false },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, reaper_cron_active: false },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, orphaned_storage_job_count: 1 },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, failed_job_count: 1 },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, expired_lease_count: 1 },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, storage_expired_lease_count: 1 },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      {
        ...HEALTHY,
        oldest_due_age_seconds: 30 * 60,
      },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      {
        ...HEALTHY,
        oldest_storage_due_age_seconds: 10 * 60,
      },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      {
        ...HEALTHY,
        oldest_pending_age_seconds: 27 * 60 * 60,
      },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      {
        ...HEALTHY,
        oldest_storage_pending_age_seconds: 36 * 60 * 60,
      },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, active_job_count: 100 },
      args,
    ),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, storage_backlog_count: 25 },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(HEALTHY, args, {
      ...RECOVERY_HEALTHY,
      expired_unacknowledged_count: 1,
      oldest_expired_at: "2026-01-01T00:00:00.000Z",
      oldest_expired_age_seconds: 1,
    }),
    "critical",
  );
  assertEquals(
    accountDeletionStatus(HEALTHY, args, {
      ...RECOVERY_HEALTHY,
      active_unacknowledged_count: 8,
      oldest_active_issued_at: "2026-07-27T00:59:00.000Z",
      oldest_active_age_seconds: 60,
      maximum_active_capabilities_per_job: 8,
    }),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      HEALTHY,
      args,
      RECOVERY_HEALTHY,
      {
        ...PREPARATION_HEALTHY,
        expired_preparation_count: 1,
        oldest_expired_age_seconds: 1,
      },
    ),
    "critical",
  );
});

Deno.test("shouldFailAccountDeletionMonitor honors severity policy", () => {
  assertEquals(shouldFailAccountDeletionMonitor("ok", "warning"), false);
  assertEquals(shouldFailAccountDeletionMonitor("warning", "warning"), true);
  assertEquals(shouldFailAccountDeletionMonitor("warning", "critical"), false);
  assertEquals(shouldFailAccountDeletionMonitor("critical", "critical"), true);
  assertEquals(shouldFailAccountDeletionMonitor("critical", "never"), false);
});

Deno.test("renderAccountDeletionMarkdown includes recovery guidance", () => {
  const unhealthy: AccountDeletionHealth = {
    ...HEALTHY,
    reaper_credentials_configured: false,
    failed_job_count: 2,
    storage_failed_job_count: 1,
  };
  const summary = buildAccountDeletionSummary(
    unhealthy,
    parseAccountDeletionMonitorArgs([]),
    new Date("2026-07-27T01:00:00.000Z"),
    {
      ...RECOVERY_HEALTHY,
      active_unacknowledged_count: 1,
      oldest_active_issued_at: "2026-07-26T00:00:00.000Z",
      oldest_active_age_seconds: 90_000,
      maximum_active_capabilities_per_job: 1,
    },
    {
      ...PREPARATION_HEALTHY,
      active_preparation_count: 1,
      oldest_active_age_seconds: 30,
    },
  );
  const markdown = renderAccountDeletionMarkdown(summary);

  assertEquals(summary.status, "critical");
  assertEquals(summary.failure_policy.should_fail, true);
  assertStringIncludes(markdown, "# Account Deletion Health");
  assertStringIncludes(markdown, "- With retry errors: `2`");
  assertStringIncludes(markdown, "- Reaper credentials configured: `false`");
  assertStringIncludes(markdown, "## Device Recovery");
  assertStringIncludes(markdown, "Recovery health availability: `available`");
  assertStringIncludes(markdown, "Active unacknowledged capabilities: `1`");
  assertStringIncludes(markdown, "Active non-destructive preparations: `1`");
  assertStringIncludes(markdown, "do not edit private job");
});

Deno.test("expand-compatible summaries expose unavailable recovery aggregates", () => {
  const summary = buildAccountDeletionSummary(
    HEALTHY,
    {
      ...parseAccountDeletionMonitorArgs([]),
      recoveryHealthMode: "expand-compatible",
    },
    new Date("2026-07-27T01:00:00.000Z"),
    null,
    null,
  );
  const markdown = renderAccountDeletionMarkdown(summary);

  assertEquals(summary.status, "ok");
  assertEquals(summary.recovery_health_availability, "not_deployed");
  assertEquals(
    summary.recovery_preparation_health_availability,
    "not_deployed",
  );
  assertEquals(summary.recovery_health, null);
  assertEquals(summary.recovery_preparation_health, null);
  assertStringIncludes(
    markdown,
    "Recovery health availability: `not_deployed`",
  );
  assertStringIncludes(markdown, "unavailable");
  assertStringIncludes(markdown, "do not infer zero recovery work");
});
