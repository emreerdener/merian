/**
 * Reads service-only account-erasure health and writes operator summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, deploy-synchronized
 *   MERIAN_SUPABASE_SERVER_API_KEY, platform SUPABASE_SECRET_KEYS,
 *   local/manual SUPABASE_SECRET_KEY, or the migration-only
 *   SUPABASE_SERVICE_ROLE_KEY fallback
 */

import { createServiceRoleClientFromEnvironmentWithOptions } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const MONITOR_REQUEST_TIMEOUT_MS = 15_000;
const MONITOR_MAXIMUM_RESPONSE_BYTES = 64 * 1_024;

export type AccountDeletionFailurePolicy = "critical" | "warning" | "never";
export type AccountDeletionStatus = "ok" | "warning" | "critical";
export type AccountDeletionRecoveryHealthMode =
  | "expand-compatible"
  | "required";
export type AccountDeletionRecoveryHealthAvailability =
  | "available"
  | "not_deployed";

export interface AccountDeletionMonitorArgs {
  warningDueAfterMinutes: number;
  criticalDueAfterMinutes: number;
  warningSlaHours: number;
  criticalSlaHours: number;
  warningBacklog: number;
  criticalBacklog: number;
  failOn: AccountDeletionFailurePolicy;
  recoveryHealthMode: AccountDeletionRecoveryHealthMode;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface AccountDeletionHealth {
  generated_at: string;
  active_job_count: number;
  pending_cleanup_count: number;
  storage_pending_count: number;
  auth_pending_count: number;
  due_job_count: number;
  failed_job_count: number;
  active_lease_count: number;
  expired_lease_count: number;
  oldest_pending_at: string | null;
  oldest_pending_age_seconds: number | null;
  oldest_due_at: string | null;
  oldest_due_age_seconds: number | null;
  storage_backlog_count: number;
  storage_due_count: number;
  storage_failed_job_count: number;
  storage_active_lease_count: number;
  storage_expired_lease_count: number;
  verification_waiting_count: number;
  orphaned_storage_job_count: number;
  oldest_storage_pending_at: string | null;
  oldest_storage_pending_age_seconds: number | null;
  oldest_storage_due_at: string | null;
  oldest_storage_due_age_seconds: number | null;
  reaper_cron_active: boolean;
  reaper_credentials_configured: boolean;
}

export interface AccountDeletionRecoveryHealth {
  generated_at: string;
  active_unacknowledged_count: number;
  acknowledged_retained_count: number;
  expired_unacknowledged_count: number;
  oldest_active_issued_at: string | null;
  oldest_active_age_seconds: number | null;
  oldest_expired_at: string | null;
  oldest_expired_age_seconds: number | null;
  maximum_active_capabilities_per_job: number;
}

export interface AccountDeletionRecoveryPreparationHealth {
  generated_at: string;
  active_preparation_count: number;
  expired_preparation_count: number;
  oldest_active_age_seconds: number | null;
  oldest_expired_age_seconds: number | null;
}

export interface AccountDeletionMonitorSummary {
  generated_at: string;
  status: AccountDeletionStatus;
  thresholds: {
    warning_due_after_minutes: number;
    critical_due_after_minutes: number;
    warning_sla_hours: number;
    critical_sla_hours: number;
    warning_backlog: number;
    critical_backlog: number;
  };
  failure_policy: {
    fail_on: AccountDeletionFailurePolicy;
    should_fail: boolean;
  };
  health: AccountDeletionHealth;
  recovery_health_availability: AccountDeletionRecoveryHealthAvailability;
  recovery_health: AccountDeletionRecoveryHealth | null;
  recovery_preparation_health_availability:
    AccountDeletionRecoveryHealthAvailability;
  recovery_preparation_health: AccountDeletionRecoveryPreparationHealth | null;
}

interface HealthRpcError {
  code: string;
  message: string;
}

if (import.meta.main) {
  const exitCode = await runAccountDeletionMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runAccountDeletionMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseAccountDeletionMonitorArgs(rawArgs);
  const supabase = createServiceRoleClientFromEnvironmentWithOptions({
    requestTimeoutMs: MONITOR_REQUEST_TIMEOUT_MS,
    maximumResponseBytes: MONITOR_MAXIMUM_RESPONSE_BYTES,
  });

  const [health, recoveryHealth, recoveryPreparationHealth] = await Promise.all(
    [
      fetchAccountDeletionHealth(supabase),
      fetchAccountDeletionRecoveryHealth(supabase, args.recoveryHealthMode),
      fetchAccountDeletionRecoveryPreparationHealth(
        supabase,
        args.recoveryHealthMode,
      ),
    ],
  );
  const summary = buildAccountDeletionSummary(
    health,
    args,
    new Date(),
    recoveryHealth,
    recoveryPreparationHealth,
  );
  printSummary(summary);
  await writeSummaryFiles(summary, args);

  if (summary.failure_policy.should_fail) {
    console.error(
      `Account deletion status=${summary.status} matched fail policy ${args.failOn}.`,
    );
    return 1;
  }
  return 0;
}

async function fetchAccountDeletionHealth(
  supabase: SupabaseClient,
): Promise<AccountDeletionHealth> {
  const { data, error } = await supabase.rpc("get_account_deletion_health");

  if (error) {
    throw new Error(
      `Account deletion health returned an error: ${error.message} (Code: ${error.code})`,
    );
  }

  return assertAccountDeletionHealth(data);
}

async function fetchAccountDeletionRecoveryHealth(
  supabase: SupabaseClient,
  mode: AccountDeletionRecoveryHealthMode,
): Promise<AccountDeletionRecoveryHealth | null> {
  const { data, error } = await supabase.rpc(
    "get_account_deletion_recovery_health",
  );
  return resolveAccountDeletionRecoveryHealthRpcResult(data, error, mode);
}

async function fetchAccountDeletionRecoveryPreparationHealth(
  supabase: SupabaseClient,
  mode: AccountDeletionRecoveryHealthMode,
): Promise<AccountDeletionRecoveryPreparationHealth | null> {
  const { data, error } = await supabase.rpc(
    "get_account_deletion_recovery_preparation_health",
  );
  return resolveAccountDeletionRecoveryPreparationHealthRpcResult(
    data,
    error,
    mode,
  );
}

export function resolveAccountDeletionRecoveryHealthRpcResult(
  data: unknown,
  error: HealthRpcError | null,
  mode: AccountDeletionRecoveryHealthMode,
): AccountDeletionRecoveryHealth | null {
  if (error === null) {
    return assertAccountDeletionRecoveryHealth(data);
  }
  if (
    isExpandCompatibleMissingHealthRpc(
      error,
      mode,
      "get_account_deletion_recovery_health",
    )
  ) {
    console.warn(
      "Account deletion recovery health is not deployed; continuing in explicit expand-compatible mode.",
    );
    return null;
  }
  throw new Error(
    `Account deletion recovery health returned an error: ${error.message} (Code: ${error.code})`,
  );
}

export function resolveAccountDeletionRecoveryPreparationHealthRpcResult(
  data: unknown,
  error: HealthRpcError | null,
  mode: AccountDeletionRecoveryHealthMode,
): AccountDeletionRecoveryPreparationHealth | null {
  if (error === null) {
    return assertAccountDeletionRecoveryPreparationHealth(data);
  }
  if (
    isExpandCompatibleMissingHealthRpc(
      error,
      mode,
      "get_account_deletion_recovery_preparation_health",
    )
  ) {
    console.warn(
      "Account deletion recovery preparation health is not deployed; continuing in explicit expand-compatible mode.",
    );
    return null;
  }
  throw new Error(
    `Account deletion preparation health returned an error: ${error.message} (Code: ${error.code})`,
  );
}

function isExpandCompatibleMissingHealthRpc(
  error: HealthRpcError,
  mode: AccountDeletionRecoveryHealthMode,
  routine: string,
): boolean {
  return mode === "expand-compatible" &&
    error.code === "PGRST202" &&
    error.message.includes(
      `function public.${routine} without parameters`,
    );
}

export function assertAccountDeletionHealth(
  value: unknown,
): AccountDeletionHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error("Account deletion health response must contain one row.");
  }
  const candidate = value[0];
  if (
    candidate === null ||
    typeof candidate !== "object" ||
    Array.isArray(candidate)
  ) {
    throw new Error("Account deletion health response row must be an object.");
  }
  const row = candidate as Record<string, unknown>;
  const health: AccountDeletionHealth = {
    generated_at: timestamp(row.generated_at, "generated_at"),
    active_job_count: count(row.active_job_count, "active_job_count"),
    pending_cleanup_count: count(
      row.pending_cleanup_count,
      "pending_cleanup_count",
    ),
    storage_pending_count: count(
      row.storage_pending_count,
      "storage_pending_count",
    ),
    auth_pending_count: count(
      row.auth_pending_count,
      "auth_pending_count",
    ),
    due_job_count: count(row.due_job_count, "due_job_count"),
    failed_job_count: count(row.failed_job_count, "failed_job_count"),
    active_lease_count: count(
      row.active_lease_count,
      "active_lease_count",
    ),
    expired_lease_count: count(
      row.expired_lease_count,
      "expired_lease_count",
    ),
    oldest_pending_at: optionalTimestamp(
      row.oldest_pending_at,
      "oldest_pending_at",
    ),
    oldest_pending_age_seconds: optionalCount(
      row.oldest_pending_age_seconds,
      "oldest_pending_age_seconds",
    ),
    oldest_due_at: optionalTimestamp(row.oldest_due_at, "oldest_due_at"),
    oldest_due_age_seconds: optionalCount(
      row.oldest_due_age_seconds,
      "oldest_due_age_seconds",
    ),
    storage_backlog_count: count(
      row.storage_backlog_count,
      "storage_backlog_count",
    ),
    storage_due_count: count(row.storage_due_count, "storage_due_count"),
    storage_failed_job_count: count(
      row.storage_failed_job_count,
      "storage_failed_job_count",
    ),
    storage_active_lease_count: count(
      row.storage_active_lease_count,
      "storage_active_lease_count",
    ),
    storage_expired_lease_count: count(
      row.storage_expired_lease_count,
      "storage_expired_lease_count",
    ),
    verification_waiting_count: count(
      row.verification_waiting_count,
      "verification_waiting_count",
    ),
    orphaned_storage_job_count: count(
      row.orphaned_storage_job_count,
      "orphaned_storage_job_count",
    ),
    oldest_storage_pending_at: optionalTimestamp(
      row.oldest_storage_pending_at,
      "oldest_storage_pending_at",
    ),
    oldest_storage_pending_age_seconds: optionalCount(
      row.oldest_storage_pending_age_seconds,
      "oldest_storage_pending_age_seconds",
    ),
    oldest_storage_due_at: optionalTimestamp(
      row.oldest_storage_due_at,
      "oldest_storage_due_at",
    ),
    oldest_storage_due_age_seconds: optionalCount(
      row.oldest_storage_due_age_seconds,
      "oldest_storage_due_age_seconds",
    ),
    reaper_cron_active: boolean(
      row.reaper_cron_active,
      "reaper_cron_active",
    ),
    reaper_credentials_configured: boolean(
      row.reaper_credentials_configured,
      "reaper_credentials_configured",
    ),
  };

  if (
    health.pending_cleanup_count +
          health.storage_pending_count +
          health.auth_pending_count !== health.active_job_count ||
    health.due_job_count > health.active_job_count ||
    health.failed_job_count > health.active_job_count ||
    health.active_lease_count + health.expired_lease_count >
      health.active_job_count ||
    health.storage_due_count > health.storage_backlog_count ||
    health.storage_failed_job_count > health.storage_backlog_count ||
    health.storage_active_lease_count + health.storage_expired_lease_count >
      health.storage_backlog_count ||
    health.verification_waiting_count > health.storage_backlog_count ||
    health.orphaned_storage_job_count > health.storage_backlog_count ||
    !pairMatchesCount(
      health.active_job_count,
      health.oldest_pending_at,
      health.oldest_pending_age_seconds,
    ) ||
    !pairMatchesCount(
      health.due_job_count,
      health.oldest_due_at,
      health.oldest_due_age_seconds,
    ) ||
    !pairMatchesCount(
      health.storage_backlog_count,
      health.oldest_storage_pending_at,
      health.oldest_storage_pending_age_seconds,
    ) ||
    !pairMatchesCount(
      health.storage_due_count,
      health.oldest_storage_due_at,
      health.oldest_storage_due_age_seconds,
    )
  ) {
    throw new Error("Account deletion health response is inconsistent.");
  }

  return health;
}

export function assertAccountDeletionRecoveryHealth(
  value: unknown,
): AccountDeletionRecoveryHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error(
      "Account deletion recovery health response must contain one row.",
    );
  }
  const candidate = value[0];
  if (
    candidate === null ||
    typeof candidate !== "object" ||
    Array.isArray(candidate)
  ) {
    throw new Error(
      "Account deletion recovery health response row must be an object.",
    );
  }
  const row = candidate as Record<string, unknown>;
  const health: AccountDeletionRecoveryHealth = {
    generated_at: timestamp(row.generated_at, "recovery.generated_at"),
    active_unacknowledged_count: count(
      row.active_unacknowledged_count,
      "recovery.active_unacknowledged_count",
    ),
    acknowledged_retained_count: count(
      row.acknowledged_retained_count,
      "recovery.acknowledged_retained_count",
    ),
    expired_unacknowledged_count: count(
      row.expired_unacknowledged_count,
      "recovery.expired_unacknowledged_count",
    ),
    oldest_active_issued_at: optionalTimestamp(
      row.oldest_active_issued_at,
      "recovery.oldest_active_issued_at",
    ),
    oldest_active_age_seconds: optionalCount(
      row.oldest_active_age_seconds,
      "recovery.oldest_active_age_seconds",
    ),
    oldest_expired_at: optionalTimestamp(
      row.oldest_expired_at,
      "recovery.oldest_expired_at",
    ),
    oldest_expired_age_seconds: optionalCount(
      row.oldest_expired_age_seconds,
      "recovery.oldest_expired_age_seconds",
    ),
    maximum_active_capabilities_per_job: count(
      row.maximum_active_capabilities_per_job,
      "recovery.maximum_active_capabilities_per_job",
    ),
  };

  if (
    !pairMatchesCount(
      health.active_unacknowledged_count,
      health.oldest_active_issued_at,
      health.oldest_active_age_seconds,
    ) ||
    !pairMatchesCount(
      health.expired_unacknowledged_count,
      health.oldest_expired_at,
      health.oldest_expired_age_seconds,
    ) ||
    health.maximum_active_capabilities_per_job >
      health.active_unacknowledged_count ||
    (health.active_unacknowledged_count === 0 &&
      health.maximum_active_capabilities_per_job !== 0)
  ) {
    throw new Error(
      "Account deletion recovery health response is inconsistent.",
    );
  }
  return health;
}

export function assertAccountDeletionRecoveryPreparationHealth(
  value: unknown,
): AccountDeletionRecoveryPreparationHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error(
      "Account deletion preparation health response must contain one row.",
    );
  }
  const candidate = value[0];
  if (
    candidate === null ||
    typeof candidate !== "object" ||
    Array.isArray(candidate)
  ) {
    throw new Error(
      "Account deletion preparation health response row must be an object.",
    );
  }
  const row = candidate as Record<string, unknown>;
  const health: AccountDeletionRecoveryPreparationHealth = {
    generated_at: timestamp(
      row.generated_at,
      "recovery_preparation.generated_at",
    ),
    active_preparation_count: count(
      row.active_preparation_count,
      "recovery_preparation.active_preparation_count",
    ),
    expired_preparation_count: count(
      row.expired_preparation_count,
      "recovery_preparation.expired_preparation_count",
    ),
    oldest_active_age_seconds: optionalCount(
      row.oldest_active_age_seconds,
      "recovery_preparation.oldest_active_age_seconds",
    ),
    oldest_expired_age_seconds: optionalCount(
      row.oldest_expired_age_seconds,
      "recovery_preparation.oldest_expired_age_seconds",
    ),
  };

  if (
    (health.active_preparation_count === 0) !==
      (health.oldest_active_age_seconds === null) ||
    (health.expired_preparation_count === 0) !==
      (health.oldest_expired_age_seconds === null)
  ) {
    throw new Error(
      "Account deletion preparation health response is inconsistent.",
    );
  }
  return health;
}

function pairMatchesCount(
  itemCount: number,
  timestampValue: string | null,
  ageSeconds: number | null,
): boolean {
  return itemCount === 0
    ? timestampValue === null && ageSeconds === null
    : timestampValue !== null && ageSeconds !== null;
}

export function accountDeletionStatus(
  health: AccountDeletionHealth,
  args: Pick<
    AccountDeletionMonitorArgs,
    | "warningDueAfterMinutes"
    | "criticalDueAfterMinutes"
    | "warningSlaHours"
    | "criticalSlaHours"
    | "warningBacklog"
    | "criticalBacklog"
  >,
  recoveryHealth: AccountDeletionRecoveryHealth | null = null,
  recoveryPreparationHealth: AccountDeletionRecoveryPreparationHealth | null =
    null,
): AccountDeletionStatus {
  const oldestDueAge = Math.max(
    health.oldest_due_age_seconds ?? 0,
    health.oldest_storage_due_age_seconds ?? 0,
  );
  const oldestPendingAge = Math.max(
    health.oldest_pending_age_seconds ?? 0,
    health.oldest_storage_pending_age_seconds ?? 0,
    recoveryHealth?.oldest_active_age_seconds ?? 0,
    recoveryPreparationHealth?.oldest_active_age_seconds ?? 0,
  );
  const backlogDepth = Math.max(
    health.active_job_count,
    health.storage_backlog_count,
    recoveryHealth?.active_unacknowledged_count ?? 0,
    recoveryPreparationHealth?.active_preparation_count ?? 0,
  );
  if (
    !health.reaper_cron_active ||
    !health.reaper_credentials_configured ||
    health.orphaned_storage_job_count > 0 ||
    (recoveryHealth?.expired_unacknowledged_count ?? 0) > 0 ||
    (recoveryPreparationHealth?.expired_preparation_count ?? 0) > 0 ||
    (recoveryHealth?.maximum_active_capabilities_per_job ?? 0) > 8 ||
    oldestDueAge >= args.criticalDueAfterMinutes * 60 ||
    oldestPendingAge >= args.criticalSlaHours * 60 * 60 ||
    backlogDepth >= args.criticalBacklog
  ) {
    return "critical";
  }
  if (
    health.failed_job_count > 0 ||
    health.storage_failed_job_count > 0 ||
    health.expired_lease_count > 0 ||
    health.storage_expired_lease_count > 0 ||
    recoveryHealth?.maximum_active_capabilities_per_job === 8 ||
    oldestDueAge >= args.warningDueAfterMinutes * 60 ||
    oldestPendingAge >= args.warningSlaHours * 60 * 60 ||
    backlogDepth >= args.warningBacklog
  ) {
    return "warning";
  }
  return "ok";
}

export function buildAccountDeletionSummary(
  health: AccountDeletionHealth,
  args: AccountDeletionMonitorArgs,
  now: Date,
  recoveryHealth: AccountDeletionRecoveryHealth | null = null,
  recoveryPreparationHealth: AccountDeletionRecoveryPreparationHealth | null =
    null,
): AccountDeletionMonitorSummary {
  const status = accountDeletionStatus(
    health,
    args,
    recoveryHealth,
    recoveryPreparationHealth,
  );
  return {
    generated_at: now.toISOString(),
    status,
    thresholds: {
      warning_due_after_minutes: args.warningDueAfterMinutes,
      critical_due_after_minutes: args.criticalDueAfterMinutes,
      warning_sla_hours: args.warningSlaHours,
      critical_sla_hours: args.criticalSlaHours,
      warning_backlog: args.warningBacklog,
      critical_backlog: args.criticalBacklog,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailAccountDeletionMonitor(status, args.failOn),
    },
    health,
    recovery_health_availability: recoveryHealth === null
      ? "not_deployed"
      : "available",
    recovery_health: recoveryHealth,
    recovery_preparation_health_availability: recoveryPreparationHealth === null
      ? "not_deployed"
      : "available",
    recovery_preparation_health: recoveryPreparationHealth,
  };
}

export function shouldFailAccountDeletionMonitor(
  status: AccountDeletionStatus,
  policy: AccountDeletionFailurePolicy,
): boolean {
  if (policy === "never") return false;
  if (policy === "warning") return status !== "ok";
  return status === "critical";
}

export function renderAccountDeletionMarkdown(
  summary: AccountDeletionMonitorSummary,
): string {
  const health = summary.health;
  const recovery = summary.recovery_health;
  const preparation = summary.recovery_preparation_health;
  return [
    "# Account Deletion Health",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Status",
    "",
    `- Health: \`${summary.status}\``,
    `- Failing this run: \`${summary.failure_policy.should_fail}\``,
    `- Fail policy: \`${summary.failure_policy.fail_on}\``,
    `- Reaper cron active: \`${health.reaper_cron_active}\``,
    `- Reaper credentials configured: \`${health.reaper_credentials_configured}\``,
    "",
    "## Account Jobs",
    "",
    `- Active: \`${health.active_job_count}\``,
    `- Pending cleanup: \`${health.pending_cleanup_count}\``,
    `- Pending storage: \`${health.storage_pending_count}\``,
    `- Pending Auth deletion: \`${health.auth_pending_count}\``,
    `- Due: \`${health.due_job_count}\``,
    `- With retry errors: \`${health.failed_job_count}\``,
    `- Active leases: \`${health.active_lease_count}\``,
    `- Expired leases: \`${health.expired_lease_count}\``,
    `- Oldest active age: \`${age(health.oldest_pending_age_seconds)}\``,
    `- Oldest due age: \`${age(health.oldest_due_age_seconds)}\``,
    "",
    "## Storage Erasure",
    "",
    `- Active: \`${health.storage_backlog_count}\``,
    `- Due: \`${health.storage_due_count}\``,
    `- Awaiting delayed verification: \`${health.verification_waiting_count}\``,
    `- With retry errors: \`${health.storage_failed_job_count}\``,
    `- Active leases: \`${health.storage_active_lease_count}\``,
    `- Expired leases: \`${health.storage_expired_lease_count}\``,
    `- Orphaned active jobs: \`${health.orphaned_storage_job_count}\``,
    `- Oldest active age: \`${
      age(health.oldest_storage_pending_age_seconds)
    }\``,
    `- Oldest due age: \`${age(health.oldest_storage_due_age_seconds)}\``,
    "",
    "## Device Recovery",
    "",
    `- Recovery health availability: \`${summary.recovery_health_availability}\``,
    `- Active unacknowledged capabilities: \`${
      recovery === null ? "unavailable" : recovery.active_unacknowledged_count
    }\``,
    `- Acknowledged idempotency receipts retained: \`${
      recovery === null ? "unavailable" : recovery.acknowledged_retained_count
    }\``,
    `- Expired unacknowledged capabilities: \`${
      recovery === null ? "unavailable" : recovery.expired_unacknowledged_count
    }\``,
    `- Maximum active capabilities for one deletion: \`${
      recovery === null
        ? "unavailable"
        : recovery.maximum_active_capabilities_per_job
    }\``,
    `- Oldest active age: \`${
      recovery === null
        ? "unavailable"
        : age(recovery.oldest_active_age_seconds)
    }\``,
    `- Oldest expired age: \`${
      recovery === null
        ? "unavailable"
        : age(recovery.oldest_expired_age_seconds)
    }\``,
    `- Preparation health availability: \`${summary.recovery_preparation_health_availability}\``,
    `- Active non-destructive preparations: \`${
      preparation === null
        ? "unavailable"
        : preparation.active_preparation_count
    }\``,
    `- Expired preparations awaiting pruning: \`${
      preparation === null
        ? "unavailable"
        : preparation.expired_preparation_count
    }\``,
    `- Oldest preparation age: \`${
      preparation === null
        ? "unavailable"
        : age(preparation.oldest_active_age_seconds)
    }\``,
    `- Oldest expired preparation age: \`${
      preparation === null
        ? "unavailable"
        : age(preparation.oldest_expired_age_seconds)
    }\``,
    "",
    "## Thresholds",
    "",
    `- Warning due age: \`${summary.thresholds.warning_due_after_minutes}m\``,
    `- Critical due age: \`${summary.thresholds.critical_due_after_minutes}m\``,
    `- Warning end-to-end SLA: \`${summary.thresholds.warning_sla_hours}h\``,
    `- Critical end-to-end SLA: \`${summary.thresholds.critical_sla_hours}h\``,
    `- Warning backlog: \`${summary.thresholds.warning_backlog}\``,
    `- Critical backlog: \`${summary.thresholds.critical_backlog}\``,
    "",
    "## Operator Action",
    "",
    summary.status === "ok" &&
      summary.recovery_health_availability === "available" &&
      summary.recovery_preparation_health_availability === "available"
      ? "No action required."
      : summary.status === "ok"
      ? "Baseline deletion health is healthy. The unavailable recovery aggregates remain in the bounded compatibility window; the scheduled resolver selects required mode after qualifying production-deploy evidence or at the hard compatibility deadline; do not infer zero recovery work from unavailable aggregates."
      : "Verify the database reaper cron and its Vault/app-settings URL and service credential, then inspect safe-delete, recover-account-deletion, reconcile-account-deletions, and R2 erasure aggregate logs. Repair configuration or dependencies and let claim-fenced retries resume; do not edit private job, capability, lease, or cursor rows.",
    "",
  ].join("\n");
}

function age(seconds: number | null): string {
  return seconds === null ? "none" : `${seconds}s`;
}

export function parseAccountDeletionMonitorArgs(
  rawArgs: string[],
): AccountDeletionMonitorArgs {
  const values = argumentValues(rawArgs);
  const warningDueAfterMinutes = parseInteger(
    values.get("warning-due-after-minutes") ?? "10",
    "--warning-due-after-minutes",
    1,
    24 * 60,
  );
  const criticalDueAfterMinutes = parseInteger(
    values.get("critical-due-after-minutes") ?? "30",
    "--critical-due-after-minutes",
    2,
    48 * 60,
  );
  const warningSlaHours = parseInteger(
    values.get("warning-sla-hours") ?? "27",
    "--warning-sla-hours",
    1,
    30 * 24,
  );
  const criticalSlaHours = parseInteger(
    values.get("critical-sla-hours") ?? "36",
    "--critical-sla-hours",
    2,
    60 * 24,
  );
  const warningBacklog = parseInteger(
    values.get("warning-backlog") ?? "25",
    "--warning-backlog",
    1,
    100_000,
  );
  const criticalBacklog = parseInteger(
    values.get("critical-backlog") ?? "100",
    "--critical-backlog",
    2,
    1_000_000,
  );
  if (criticalDueAfterMinutes <= warningDueAfterMinutes) {
    throw new Error(
      "--critical-due-after-minutes must exceed --warning-due-after-minutes.",
    );
  }
  if (criticalSlaHours <= warningSlaHours) {
    throw new Error("--critical-sla-hours must exceed --warning-sla-hours.");
  }
  if (criticalBacklog <= warningBacklog) {
    throw new Error("--critical-backlog must exceed --warning-backlog.");
  }

  return {
    warningDueAfterMinutes,
    criticalDueAfterMinutes,
    warningSlaHours,
    criticalSlaHours,
    warningBacklog,
    criticalBacklog,
    failOn: parseFailurePolicy(values.get("fail-on") ?? "warning"),
    recoveryHealthMode: parseRecoveryHealthMode(
      values.get("recovery-health-mode") ?? "required",
    ),
    summaryJsonPath: optionalPath(
      values.get("summary-json"),
      "--summary-json",
    ),
    summaryMarkdownPath: optionalPath(
      values.get("summary-md"),
      "--summary-md",
    ),
  };
}

function argumentValues(rawArgs: string[]): Map<string, string | boolean> {
  const supported = new Set([
    "warning-due-after-minutes",
    "critical-due-after-minutes",
    "warning-sla-hours",
    "critical-sla-hours",
    "warning-backlog",
    "critical-backlog",
    "fail-on",
    "recovery-health-mode",
    "summary-json",
    "summary-md",
  ]);
  const values = new Map<string, string | boolean>();
  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const [key, inlineValue] = argument.slice(2).split("=", 2);
    if (!supported.has(key)) {
      throw new Error(`Unsupported argument: --${key}`);
    }
    if (inlineValue !== undefined) {
      values.set(key, inlineValue);
    } else if (
      rawArgs[index + 1] !== undefined &&
      !rawArgs[index + 1].startsWith("--")
    ) {
      values.set(key, rawArgs[index + 1]);
      index += 1;
    } else {
      values.set(key, true);
    }
  }
  return values;
}

function timestamp(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(`Account deletion health has invalid ${field}.`);
  }
  return value;
}

function optionalTimestamp(value: unknown, field: string): string | null {
  return value === null ? null : timestamp(value, field);
}

function count(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(`Account deletion health has invalid ${field}.`);
  }
  return value;
}

function optionalCount(value: unknown, field: string): number | null {
  return value === null ? null : count(value, field);
}

function boolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`Account deletion health has invalid ${field}.`);
  }
  return value;
}

function parseInteger(
  value: string | boolean,
  label: string,
  min: number,
  max: number,
): number {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} must be an integer.`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${label} must be from ${min} to ${max}.`);
  }
  return parsed;
}

function parseFailurePolicy(
  value: string | boolean,
): AccountDeletionFailurePolicy {
  if (typeof value !== "string") {
    throw new Error("--fail-on must be critical, warning, or never.");
  }
  const normalized = value.toLowerCase();
  if (
    normalized === "critical" ||
    normalized === "warning" ||
    normalized === "never"
  ) {
    return normalized;
  }
  throw new Error("--fail-on must be critical, warning, or never.");
}

function parseRecoveryHealthMode(
  value: string | boolean,
): AccountDeletionRecoveryHealthMode {
  if (value === "expand-compatible" || value === "required") {
    return value;
  }
  throw new Error(
    "--recovery-health-mode must be expand-compatible or required.",
  );
}

function optionalPath(
  value: string | boolean | undefined,
  label: string,
): string | null {
  if (value === undefined) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty path.`);
  }
  return value;
}

async function writeSummaryFiles(
  summary: AccountDeletionMonitorSummary,
  args: AccountDeletionMonitorArgs,
): Promise<void> {
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  }
  if (args.summaryMarkdownPath) {
    await Deno.writeTextFile(
      args.summaryMarkdownPath,
      `${renderAccountDeletionMarkdown(summary)}\n`,
    );
  }
}

function printSummary(summary: AccountDeletionMonitorSummary): void {
  console.log("Account deletion health monitor complete");
  console.log(`status: ${summary.status}`);
  console.log(`active_job_count: ${summary.health.active_job_count}`);
  console.log(`due_job_count: ${summary.health.due_job_count}`);
  console.log(`failed_job_count: ${summary.health.failed_job_count}`);
  console.log(
    `storage_backlog_count: ${summary.health.storage_backlog_count}`,
  );
  console.log(
    `recovery_health_availability: ${summary.recovery_health_availability}`,
  );
  console.log(
    `recovery_active_unacknowledged_count: ${
      summary.recovery_health?.active_unacknowledged_count ?? "unavailable"
    }`,
  );
  console.log(
    `recovery_expired_unacknowledged_count: ${
      summary.recovery_health?.expired_unacknowledged_count ?? "unavailable"
    }`,
  );
  console.log(
    `recovery_preparation_health_availability: ${summary.recovery_preparation_health_availability}`,
  );
  console.log(
    `storage_failed_job_count: ${summary.health.storage_failed_job_count}`,
  );
  console.log(
    `expired_lease_count: ${
      summary.health.expired_lease_count +
      summary.health.storage_expired_lease_count
    }`,
  );
  console.log(`should_fail: ${summary.failure_policy.should_fail}`);
}
