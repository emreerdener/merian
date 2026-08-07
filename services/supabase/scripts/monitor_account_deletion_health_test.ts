import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  type AccountDeletionHealth,
  accountDeletionStatus,
  assertAccountDeletionHealth,
  buildAccountDeletionSummary,
  parseAccountDeletionMonitorArgs,
  renderAccountDeletionMarkdown,
  shouldFailAccountDeletionMonitor,
} from "./monitor_account_deletion_health.ts";

const HEALTHY: AccountDeletionHealth = {
  generated_at: "2026-07-27T01:00:00.000Z",
  active_job_count: 0,
  pending_cleanup_count: 0,
  storage_pending_count: 0,
  auth_pending_count: 0,
  manual_revocation_delivery_pending_count: 0,
  manual_revocation_delivery_accepted_count: 0,
  manual_revocation_delivery_delayed_count: 0,
  manual_revocation_delivery_retry_required_count: 0,
  manual_revocation_delivery_delivered_count: 0,
  manual_revocation_delivery_unverifiable_count: 0,
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

Deno.test("parseAccountDeletionMonitorArgs applies deletion SLA defaults", () => {
  assertEquals(parseAccountDeletionMonitorArgs([]), {
    warningDueAfterMinutes: 10,
    criticalDueAfterMinutes: 30,
    warningSlaHours: 27,
    criticalSlaHours: 36,
    warningBacklog: 25,
    criticalBacklog: 100,
    failOn: "warning",
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
  assertThrows(() => parseAccountDeletionMonitorArgs(["--unknown", "1"]));
});

Deno.test("assertAccountDeletionHealth validates one consistent summary", () => {
  const active: AccountDeletionHealth = {
    ...HEALTHY,
    active_job_count: 3,
    pending_cleanup_count: 1,
    storage_pending_count: 1,
    auth_pending_count: 1,
    manual_revocation_delivery_pending_count: 1,
    manual_revocation_delivery_accepted_count: 1,
    manual_revocation_delivery_delayed_count: 1,
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
      {
        ...HEALTHY,
        manual_revocation_delivery_unverifiable_count: 1,
      },
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
      { ...HEALTHY, manual_revocation_delivery_delayed_count: 1 },
      args,
    ),
    "warning",
  );
  assertEquals(
    accountDeletionStatus(
      { ...HEALTHY, manual_revocation_delivery_retry_required_count: 1 },
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
    active_job_count: 2,
    auth_pending_count: 2,
    failed_job_count: 2,
    due_job_count: 1,
    oldest_pending_at: "2026-07-27T00:00:00.000Z",
    oldest_pending_age_seconds: 3_600,
    oldest_due_at: "2026-07-27T00:59:00.000Z",
    oldest_due_age_seconds: 60,
    manual_revocation_delivery_pending_count: 2,
    manual_revocation_delivery_accepted_count: 1,
    manual_revocation_delivery_delayed_count: 1,
    manual_revocation_delivery_retry_required_count: 1,
    manual_revocation_delivery_delivered_count: 4,
  };
  assertEquals(assertAccountDeletionHealth([unhealthy]), unhealthy);
  const summary = buildAccountDeletionSummary(
    unhealthy,
    parseAccountDeletionMonitorArgs([]),
    new Date("2026-07-27T01:00:00.000Z"),
  );
  const markdown = renderAccountDeletionMarkdown(summary);

  assertEquals(summary.status, "critical");
  assertEquals(summary.failure_policy.should_fail, true);
  assertStringIncludes(markdown, "# Account Deletion Health");
  assertStringIncludes(markdown, "- With retry errors: `2`");
  assertStringIncludes(
    markdown,
    "- Pending legacy Apple instruction delivery: `2`",
  );
  assertStringIncludes(
    markdown,
    "- Accepted legacy Apple deliveries awaiting confirmation: `1`",
  );
  assertStringIncludes(
    markdown,
    "- Provider-delayed legacy Apple deliveries: `1`",
  );
  assertStringIncludes(
    markdown,
    "- Legacy Apple deliveries requiring a retry: `1`",
  );
  assertStringIncludes(
    markdown,
    "- Delivery-confirmed legacy Apple instructions: `4`",
  );
  assertStringIncludes(markdown, "- Reaper credentials configured: `false`");
  assertStringIncludes(markdown, "do not edit private job");
});
