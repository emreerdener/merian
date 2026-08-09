/**
 * Reads owner-only Ghost profile merge health without emitting receipt,
 * identity, proof, or provider identifiers.
 *
 * Required env:
 *   MERIAN_DATABASE_URL
 */

import postgres from "npm:postgres@3.4.7";

const DATABASE_CONNECT_TIMEOUT_SECONDS = 10;
const DATABASE_IDLE_TIMEOUT_SECONDS = 5;
const DATABASE_MAX_LIFETIME_SECONDS = 30;
const DATABASE_END_TIMEOUT_SECONDS = 5;

export type GhostMergeHealthStatus = "ok" | "warning" | "critical";
export type GhostMergeFailurePolicy = "critical" | "warning" | "never";

export interface GhostMergeMonitorArgs {
  cleanupWarningAfterMinutes: number;
  cleanupCriticalAfterMinutes: number;
  failOn: GhostMergeFailurePolicy;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface GhostMergeHealth {
  generated_at: string;
  recent_prepared_count: number;
  recent_merged_count: number;
  recent_expired_count: number;
  oldest_recent_prepared_age_seconds: number | null;
  cleanup_pending_count: number;
  cleanup_overdue_count: number;
  cleanup_error_count: number;
  oldest_cleanup_age_seconds: number | null;
  missing_destination_queue_count: number;
  misdirected_destination_queue_count: number;
  unrefreshed_destination_queue_count: number;
}

export interface GhostMergeMonitorSummary {
  generated_at: string;
  status: GhostMergeHealthStatus;
  windows: {
    recent_handoffs_hours: 12;
    destination_queue_hours: 24;
  };
  thresholds: {
    cleanup_warning_after_minutes: number;
    cleanup_critical_after_minutes: number;
  };
  failure_policy: {
    fail_on: GhostMergeFailurePolicy;
    should_fail: boolean;
  };
  health: GhostMergeHealth;
}

if (import.meta.main) {
  const databaseUrl = Deno.env.get("MERIAN_DATABASE_URL") ?? "";
  try {
    const exitCode = await runGhostMergeMonitor(Deno.args);
    Deno.exit(exitCode);
  } catch (error) {
    const rawMessage = error instanceof Error ? error.message : String(error);
    const safeMessage = databaseUrl.length > 0
      ? rawMessage.replaceAll(databaseUrl, "[redacted]")
      : rawMessage;
    console.error(`Ghost profile merge health monitor failed: ${safeMessage}`);
    Deno.exit(2);
  }
}

export async function runGhostMergeMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseGhostMergeMonitorArgs(rawArgs);
  const databaseUrl = requiredEnv("MERIAN_DATABASE_URL");
  const health = await inspectGhostMergeHealth(
    databaseUrl,
    args.cleanupWarningAfterMinutes,
  );
  const summary = buildGhostMergeMonitorSummary(health, args);

  printSummary(summary);
  await writeSummaryFiles(summary, args);

  if (summary.failure_policy.should_fail) {
    console.error(
      `Ghost profile merge status=${summary.status} matched fail policy ${args.failOn}.`,
    );
    return 1;
  }
  return 0;
}

export async function inspectGhostMergeHealth(
  databaseUrl: string,
  cleanupWarningAfterMinutes: number,
): Promise<GhostMergeHealth> {
  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    connect_timeout: DATABASE_CONNECT_TIMEOUT_SECONDS,
    idle_timeout: DATABASE_IDLE_TIMEOUT_SECONDS,
    max_lifetime: DATABASE_MAX_LIFETIME_SECONDS,
  });
  let transactionStarted = false;

  try {
    await sql.unsafe("BEGIN TRANSACTION READ ONLY");
    transactionStarted = true;
    await sql.unsafe("SET LOCAL statement_timeout = '10s'");
    await sql.unsafe("SET LOCAL idle_in_transaction_session_timeout = '15s'");

    const rows = await sql.unsafe(
      `
        WITH health_clock AS (
          SELECT pg_catalog.CLOCK_TIMESTAMP() AS observed_at
        ),
        recent_handoffs AS (
          SELECT
            (
              COUNT(*) FILTER (WHERE handoff.status = 'prepared')
            )::INTEGER AS recent_prepared_count,
            (
              COUNT(*) FILTER (WHERE handoff.status = 'merged')
            )::INTEGER AS recent_merged_count,
            (
              COUNT(*) FILTER (WHERE handoff.status = 'expired')
            )::INTEGER AS recent_expired_count,
            CASE
              WHEN MIN(handoff.created_at) FILTER (
                WHERE handoff.status = 'prepared'
              ) IS NULL THEN NULL
              ELSE pg_catalog.FLOOR(
                pg_catalog.DATE_PART(
                  'epoch',
                  clock.observed_at - (
                    MIN(handoff.created_at)
                      FILTER (WHERE handoff.status = 'prepared')
                  )
                )
              )::INTEGER
            END AS oldest_recent_prepared_age_seconds
          FROM health_clock AS clock
          LEFT JOIN internal.ghost_profile_merge_handoffs AS handoff
            ON handoff.status IN ('prepared', 'merged', 'expired')
           AND handoff.created_at
             >= clock.observed_at - INTERVAL '12 hours'
          GROUP BY clock.observed_at
        ),
        cleanup_health AS (
          SELECT
            COUNT(handoff.id)::INTEGER AS cleanup_pending_count,
            (
              COUNT(*) FILTER (
                WHERE handoff.merged_at
                  <= clock.observed_at
                    - ($1::INTEGER * INTERVAL '1 minute')
              )
            )::INTEGER AS cleanup_overdue_count,
            (
              COUNT(*) FILTER (
                WHERE handoff.last_cleanup_error_code IS NOT NULL
              )
            )::INTEGER AS cleanup_error_count,
            CASE
              WHEN MIN(handoff.merged_at) IS NULL THEN NULL
              ELSE pg_catalog.FLOOR(
                pg_catalog.DATE_PART(
                  'epoch',
                  clock.observed_at - MIN(handoff.merged_at)
                )
              )::INTEGER
            END AS oldest_cleanup_age_seconds
          FROM health_clock AS clock
          LEFT JOIN internal.ghost_profile_merge_handoffs AS handoff
            ON handoff.status = 'merged'
           AND handoff.auth_deleted_at IS NULL
          GROUP BY clock.observed_at
        ),
        destination_queue_health AS (
          SELECT
            (
              COUNT(handoff.id) FILTER (
                WHERE queue.merian_user_id IS NULL
              )
            )::INTEGER AS missing_destination_queue_count,
            (
              COUNT(handoff.id) FILTER (
                WHERE queue.merian_user_id IS NOT NULL
                  AND queue.lookup_app_user_id
                    IS DISTINCT FROM
                      internal.canonical_revenuecat_app_user_id(
                        handoff.target_user_id
                      )
              )
            )::INTEGER AS misdirected_destination_queue_count,
            (
              COUNT(handoff.id) FILTER (
                WHERE queue.merian_user_id IS NOT NULL
                  AND queue.updated_at < handoff.merged_at
              )
            )::INTEGER AS unrefreshed_destination_queue_count
          FROM health_clock AS clock
          LEFT JOIN internal.ghost_profile_merge_handoffs AS handoff
            ON handoff.status = 'merged'
           AND handoff.merged_at
             >= clock.observed_at - INTERVAL '24 hours'
          LEFT JOIN internal.revenuecat_reconciliation_queue AS queue
            ON queue.merian_user_id = handoff.target_user_id
        )
        SELECT
          clock.observed_at::TEXT AS generated_at,
          recent.recent_prepared_count,
          recent.recent_merged_count,
          recent.recent_expired_count,
          recent.oldest_recent_prepared_age_seconds,
          cleanup.cleanup_pending_count,
          cleanup.cleanup_overdue_count,
          cleanup.cleanup_error_count,
          cleanup.oldest_cleanup_age_seconds,
          queue_health.missing_destination_queue_count,
          queue_health.misdirected_destination_queue_count,
          queue_health.unrefreshed_destination_queue_count
        FROM health_clock AS clock
        CROSS JOIN recent_handoffs AS recent
        CROSS JOIN cleanup_health AS cleanup
        CROSS JOIN destination_queue_health AS queue_health
      `,
      [cleanupWarningAfterMinutes],
    );

    const health = assertGhostMergeHealth(rows);
    await sql.unsafe("COMMIT");
    transactionStarted = false;
    return health;
  } catch (error) {
    if (transactionStarted) {
      await sql.unsafe("ROLLBACK").catch(() => undefined);
    }
    throw error;
  } finally {
    await sql.end({ timeout: DATABASE_END_TIMEOUT_SECONDS });
  }
}

export function assertGhostMergeHealth(value: unknown): GhostMergeHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error("Ghost merge health response must contain one row.");
  }
  const row = value[0] as Record<string, unknown>;
  const health: GhostMergeHealth = {
    generated_at: timestamp(row.generated_at, "generated_at"),
    recent_prepared_count: nonnegativeInteger(
      row.recent_prepared_count,
      "recent_prepared_count",
    ),
    recent_merged_count: nonnegativeInteger(
      row.recent_merged_count,
      "recent_merged_count",
    ),
    recent_expired_count: nonnegativeInteger(
      row.recent_expired_count,
      "recent_expired_count",
    ),
    oldest_recent_prepared_age_seconds: nullableNonnegativeInteger(
      row.oldest_recent_prepared_age_seconds,
      "oldest_recent_prepared_age_seconds",
    ),
    cleanup_pending_count: nonnegativeInteger(
      row.cleanup_pending_count,
      "cleanup_pending_count",
    ),
    cleanup_overdue_count: nonnegativeInteger(
      row.cleanup_overdue_count,
      "cleanup_overdue_count",
    ),
    cleanup_error_count: nonnegativeInteger(
      row.cleanup_error_count,
      "cleanup_error_count",
    ),
    oldest_cleanup_age_seconds: nullableNonnegativeInteger(
      row.oldest_cleanup_age_seconds,
      "oldest_cleanup_age_seconds",
    ),
    missing_destination_queue_count: nonnegativeInteger(
      row.missing_destination_queue_count,
      "missing_destination_queue_count",
    ),
    misdirected_destination_queue_count: nonnegativeInteger(
      row.misdirected_destination_queue_count,
      "misdirected_destination_queue_count",
    ),
    unrefreshed_destination_queue_count: nonnegativeInteger(
      row.unrefreshed_destination_queue_count,
      "unrefreshed_destination_queue_count",
    ),
  };

  if (
    (health.recent_prepared_count === 0) !==
      (health.oldest_recent_prepared_age_seconds === null) ||
    (health.cleanup_pending_count === 0) !==
      (health.oldest_cleanup_age_seconds === null) ||
    health.cleanup_overdue_count > health.cleanup_pending_count ||
    health.cleanup_error_count > health.cleanup_pending_count
  ) {
    throw new Error("Ghost merge health response is inconsistent.");
  }
  return health;
}

export function ghostMergeHealthStatus(
  health: GhostMergeHealth,
  cleanupWarningAfterMinutes: number,
  cleanupCriticalAfterMinutes: number,
): GhostMergeHealthStatus {
  if (
    health.missing_destination_queue_count > 0 ||
    health.misdirected_destination_queue_count > 0 ||
    health.unrefreshed_destination_queue_count > 0 ||
    (health.oldest_cleanup_age_seconds ?? 0) >=
      cleanupCriticalAfterMinutes * 60
  ) {
    return "critical";
  }
  if (
    health.cleanup_overdue_count > 0 ||
    health.cleanup_error_count > 0 ||
    (health.oldest_cleanup_age_seconds ?? 0) >=
      cleanupWarningAfterMinutes * 60
  ) {
    return "warning";
  }
  return "ok";
}

export function buildGhostMergeMonitorSummary(
  health: GhostMergeHealth,
  args: GhostMergeMonitorArgs,
): GhostMergeMonitorSummary {
  const status = ghostMergeHealthStatus(
    health,
    args.cleanupWarningAfterMinutes,
    args.cleanupCriticalAfterMinutes,
  );
  return {
    generated_at: health.generated_at,
    status,
    windows: {
      recent_handoffs_hours: 12,
      destination_queue_hours: 24,
    },
    thresholds: {
      cleanup_warning_after_minutes: args.cleanupWarningAfterMinutes,
      cleanup_critical_after_minutes: args.cleanupCriticalAfterMinutes,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailGhostMergeMonitor(status, args.failOn),
    },
    health,
  };
}

export function shouldFailGhostMergeMonitor(
  status: GhostMergeHealthStatus,
  policy: GhostMergeFailurePolicy,
): boolean {
  if (policy === "never") return false;
  if (policy === "warning") return status !== "ok";
  return status === "critical";
}

export function renderGhostMergeMonitorMarkdown(
  summary: GhostMergeMonitorSummary,
): string {
  const preparedAge = summary.health.oldest_recent_prepared_age_seconds === null
    ? "none"
    : `${summary.health.oldest_recent_prepared_age_seconds}s`;
  const cleanupAge = summary.health.oldest_cleanup_age_seconds === null
    ? "none"
    : `${summary.health.oldest_cleanup_age_seconds}s`;
  return [
    "# Ghost Profile Merge Health",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Status",
    "",
    `- Health: \`${summary.status}\``,
    `- Failing this run: \`${summary.failure_policy.should_fail}\``,
    `- Fail policy: \`${summary.failure_policy.fail_on}\``,
    "",
    "## Last 12 Hours",
    "",
    `- Prepared receipts: \`${summary.health.recent_prepared_count}\``,
    `- Merged receipts: \`${summary.health.recent_merged_count}\``,
    `- Expired receipts: \`${summary.health.recent_expired_count}\``,
    `- Oldest recent prepared age: \`${preparedAge}\``,
    "",
    "## Cleanup and Provider Repair",
    "",
    `- Auth cleanup pending: \`${summary.health.cleanup_pending_count}\``,
    `- Auth cleanup overdue: \`${summary.health.cleanup_overdue_count}\``,
    `- Pending cleanup errors: \`${summary.health.cleanup_error_count}\``,
    `- Oldest cleanup age: \`${cleanupAge}\``,
    `- Missing destination RevenueCat queues: \`${summary.health.missing_destination_queue_count}\``,
    `- Misdirected destination RevenueCat queues: \`${summary.health.misdirected_destination_queue_count}\``,
    `- Unrefreshed destination RevenueCat queues: \`${summary.health.unrefreshed_destination_queue_count}\``,
    "",
    "## Operator Action",
    "",
    summary.status === "ok"
      ? "No repair is required. If prepared receipts are present, confirm retryable merge telemetry is draining and proof-capable clients retain and retry their Keychain queue."
      : "Inspect merge, Auth-cleanup, and RevenueCat reconciliation logs; confirm proof-capable clients retain and retry their Keychain queue. Preserve receipts and client proofs, deploy only reviewed forward fixes, and let idempotent workers retry. Do not edit receipt state, delete proofs, or manually reparent user data.",
    "",
    "This summary contains aggregate counts only. Do not add handoff IDs, user IDs, proof hashes, or provider subjects to monitor artifacts.",
    "",
  ].join("\n");
}

export function parseGhostMergeMonitorArgs(
  rawArgs: string[],
): GhostMergeMonitorArgs {
  const values = argumentValues(rawArgs);
  const cleanupWarningAfterMinutes = parseInteger(
    values.get("cleanup-warning-after-minutes") ?? "20",
    "--cleanup-warning-after-minutes",
    1,
    24 * 60,
  );
  const cleanupCriticalAfterMinutes = parseInteger(
    values.get("cleanup-critical-after-minutes") ?? "60",
    "--cleanup-critical-after-minutes",
    2,
    48 * 60,
  );
  if (cleanupCriticalAfterMinutes <= cleanupWarningAfterMinutes) {
    throw new Error(
      "--cleanup-critical-after-minutes must exceed --cleanup-warning-after-minutes.",
    );
  }

  return {
    cleanupWarningAfterMinutes,
    cleanupCriticalAfterMinutes,
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
    "cleanup-warning-after-minutes",
    "cleanup-critical-after-minutes",
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

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable ${name}.`);
  }
  return value;
}

function timestamp(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(`Ghost merge health has invalid ${field}.`);
  }
  return value;
}

function nonnegativeInteger(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(`Ghost merge health has invalid ${field}.`);
  }
  return value;
}

function nullableNonnegativeInteger(
  value: unknown,
  field: string,
): number | null {
  return value === null ? null : nonnegativeInteger(value, field);
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
): GhostMergeFailurePolicy {
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
  summary: GhostMergeMonitorSummary,
  args: GhostMergeMonitorArgs,
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
      `${renderGhostMergeMonitorMarkdown(summary)}\n`,
    );
  }
}

function printSummary(summary: GhostMergeMonitorSummary): void {
  console.log("Ghost profile merge health monitor complete");
  console.log(`status: ${summary.status}`);
  console.log(
    `recent_prepared_count: ${summary.health.recent_prepared_count}`,
  );
  console.log(
    `cleanup_overdue_count: ${summary.health.cleanup_overdue_count}`,
  );
  console.log(
    `missing_destination_queue_count: ${summary.health.missing_destination_queue_count}`,
  );
  console.log(
    `misdirected_destination_queue_count: ${summary.health.misdirected_destination_queue_count}`,
  );
  console.log(
    `unrefreshed_destination_queue_count: ${summary.health.unrefreshed_destination_queue_count}`,
  );
  console.log(`should_fail: ${summary.failure_policy.should_fail}`);
}
