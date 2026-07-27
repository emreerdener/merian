/**
 * Reads service-only account-erasure health and writes operator summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, platform SUPABASE_SECRET_KEYS, or the migration-only
 *   SUPABASE_SERVICE_ROLE_KEY fallback
 */

import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../functions/_shared/serviceRoleAuth.ts";

export type AccountDeletionFailurePolicy = "critical" | "warning" | "never";
export type AccountDeletionStatus = "ok" | "warning" | "critical";

export interface AccountDeletionMonitorArgs {
  warningDueAfterMinutes: number;
  criticalDueAfterMinutes: number;
  warningSlaHours: number;
  criticalSlaHours: number;
  warningBacklog: number;
  criticalBacklog: number;
  failOn: AccountDeletionFailurePolicy;
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
}

const RESPONSE_DEADLINE_MS = 15_000;
const MAXIMUM_RESPONSE_BYTES = 64 * 1_024;

if (import.meta.main) {
  const exitCode = await runAccountDeletionMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runAccountDeletionMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseAccountDeletionMonitorArgs(rawArgs);
  const supabaseUrl = requiredEnv("SUPABASE_URL").trim().replace(/\/$/, "");
  const serverApiKey = requireServerApiKeyFromEnvironment();

  const health = await fetchAccountDeletionHealth(
    `${supabaseUrl}/rest/v1/rpc/get_account_deletion_health`,
    serverApiKey,
  );
  const summary = buildAccountDeletionSummary(health, args, new Date());
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
  url: string,
  serverApiKey: string,
): Promise<AccountDeletionHealth> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RESPONSE_DEADLINE_MS);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...serviceRoleRequestHeaders(serverApiKey, "database"),
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: controller.signal,
    });
    const text = await readBoundedResponse(response);
    let json: unknown;
    try {
      json = text.length === 0 ? null : JSON.parse(text);
    } catch {
      throw new Error(
        `Account deletion health returned invalid JSON (HTTP ${response.status}).`,
      );
    }
    if (!response.ok) {
      throw new Error(
        `Account deletion health returned HTTP ${response.status}.`,
      );
    }
    return assertAccountDeletionHealth(json);
  } finally {
    clearTimeout(timeout);
  }
}

async function readBoundedResponse(response: Response): Promise<string> {
  const declaredLength = response.headers.get("Content-Length");
  if (
    declaredLength !== null &&
    /^\d+$/.test(declaredLength) &&
    Number(declaredLength) > MAXIMUM_RESPONSE_BYTES
  ) {
    await response.body?.cancel();
    throw new Error("Account deletion health response is too large.");
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > MAXIMUM_RESPONSE_BYTES) {
        await reader.cancel();
        throw new Error("Account deletion health response is too large.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const combined = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(combined);
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
): AccountDeletionStatus {
  const oldestDueAge = Math.max(
    health.oldest_due_age_seconds ?? 0,
    health.oldest_storage_due_age_seconds ?? 0,
  );
  const oldestPendingAge = Math.max(
    health.oldest_pending_age_seconds ?? 0,
    health.oldest_storage_pending_age_seconds ?? 0,
  );
  const backlogDepth = Math.max(
    health.active_job_count,
    health.storage_backlog_count,
  );
  if (
    !health.reaper_cron_active ||
    !health.reaper_credentials_configured ||
    health.orphaned_storage_job_count > 0 ||
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
): AccountDeletionMonitorSummary {
  const status = accountDeletionStatus(health, args);
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
    summary.status === "ok"
      ? "No action required."
      : "Verify the database reaper cron and its Vault/app-settings URL and service credential, then inspect safe-delete, reconcile-account-deletions, and R2 erasure logs. Repair configuration or dependencies and let claim-fenced retries resume; do not edit private job, lease, or cursor rows.",
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

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env ${name}.`);
  return value;
}
